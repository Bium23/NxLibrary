import NXLibraryCore

extension AppViewModel {
    func personalizationKey(for game: PortedGame) -> String { personalizations.nxnativeKey(for: game) }

    /// One reported failure, with a reload action instead of saving displayed
    /// rows over an unreadable or newer catalog. Build retries keep their result.
    func reportCatalogFailure(_ error: Error) {
        logs.append(LogEntry(level: .error, message: error.localizedDescription))
        showSettingsNotice(title: L10n.text("Library not saved"), message: error.localizedDescription,
                           retry: { [weak self] in self?.reloadCatalog() })
    }

    func reloadCatalog() {
        do { applyCatalog(try catalogRepository.load()) }
        catch { reportCatalogFailure(error) }
    }

    @discardableResult
    func persistBuildOutcome(_ game: PortedGame, retrying: Bool = false) -> Bool {
        if retrying {
            guard !isBuilding, catalogBuildRecoveries[game.id] == game else {
                reportCatalogFailure(CatalogStoreError.staleRevision)
                return false
            }
        } else { catalogBuildRecoveries.retain(game) }
        do {
            applyCatalog(try catalogRepository.recordNXNativeBuild(game))
            catalogBuildRecoveries.acknowledge(id: game.id, matching: game)
            return true
        } catch {
            logs.append(LogEntry(level: .error, message: error.localizedDescription))
            if game.pendingInstall != nil {
                presentInstallFailure(for: game, error: error.localizedDescription)
                return false
            }
            showSettingsNotice(title: L10n.text("Library not saved"),
                               message: L10n.text("The build result is kept for this session. Free space if needed, then retry saving before closing NX Library."),
                               retry: { [weak self] in _ = self?.persistBuildOutcome(game, retrying: true) })
            return false
        }
    }

    func retrySavingBuildResults() {
        guard !isBuilding else { return }
        for result in catalogBuildRecoveries.values {
            if !persistBuildOutcome(result, retrying: true) { break }
        }
    }

}
