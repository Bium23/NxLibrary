import NXLibraryCore

/// Prepared before the shell enters SwiftUI's view graph. Model startup can
/// update AppKit and shared observable services; it must not run during a view's
/// StateObject creation while the prepared shell enters the view graph.
@MainActor
final class AppShellState {
    let settings: AppSettingsStore
    let viewModel: AppViewModel
    let router: AppRouter
    let sources: CatalogSourcesModel
    /// "Welcome to Arcane" is up from the first frame, so the library never shows before it. Decided before save recovery starts; what it raises opens above.
    let opensWithWelcome: Bool

    init(settings: AppSettingsStore, catalog: CatalogDocument, repository: CatalogRepository) {
        self.settings = settings
        AppLocalization.shared.configure(settings.settings)
        ThemeStore.shared.apply(id: settings.settings.colorThemeID)
        let model = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository)
        viewModel = model
        AppDelegate.isBusy = { [weak model] in
            guard let model else { return false }
            return model.isBuilding || model.isUpdatingApp || model.hasActiveSaveOperations
        }
        sources = CatalogSourcesModel(repository: repository, initialConfiguration: catalog.source(.steam) ?? .init(integration: .steam)) { [weak model] document in
            model?.applyCatalog(document)
        }
        let router = AppRouter()
        router.setInitialRoute(AppRouter.initialRoute(for: settings.settings.startOn, last: settings.settings.lastHome))
        self.router = router
        opensWithWelcome = ArcaneWelcome.shouldShow(setupCompleted: model.setupCompleted,
                                                    shown: settings.settings.welcomeArcaneShown,
                                                    hasPendingRecovery: false)
        model.isWelcomeOpen = opensWithWelcome
    }
}
