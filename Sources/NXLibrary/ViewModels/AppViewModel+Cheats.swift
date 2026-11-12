import AppKit
import NXLibraryCore

/// What the Cheats row, panel, detail label and diagnostics know about one game's cheats.
struct CheatContext {
    /// Nil exactly when the status is not `.ready`.
    let store: CheatStore?
    let status: CheatStatus
    let buildID: String?
    let titleID: String?
    let version: String?
}

/// Cheats: whether a game's app can use them, its files as the
/// host reads them, and what to do with files the player adds. Writes go through `CheatStore`, only while the game is
/// not running.
extension AppViewModel {
    /// Engine ancestry answers and states read from disk, per launch of NX Library. The state is read again whenever
    /// the files' fingerprint changes, so the panel, the host and a hand edit are all seen.
    private final class CheatCache {
        var ancestry: (path: String, value: EngineAncestry)?
        var states: [UUID: (fingerprint: [String], state: CheatState)] = [:]
    }

    private static let cheatCache = CheatCache()

    private func engineAncestry() -> EngineAncestry {
        let cache = Self.cheatCache
        if let known = cache.ancestry, known.path == nxnativePath { return known.value }
        let value = EngineAncestry(runner: SystemCommandRunner(), engineFolder: URL(fileURLWithPath: nxnativePath))
        cache.ancestry = (nxnativePath, value)
        return value
    }

    func cheatContext(for game: PortedGame) -> CheatContext {
        let buildID = CheatLocator.buildID(appURL: game.url)
        let titleID = CheatLocator.titleID(appURL: game.url, fallback: game.titleId)
        let ancestry = engineAncestry()
        // An imported app has no build record: the commit its packer wrote says which engine it carries.
        let engineCommit = CheatLocator.engineCommit(appURL: game.url, recorded: game.lastBuild?.engineCommit)
        var status = CheatStatus.of(engineCommit: engineCommit, buildID: buildID, titleID: titleID,
                                    isAncestor: { ancestry.contains(CheatStatus.cheatsCommit, in: $0) })
        var store: CheatStore?
        if status == .ready, let buildID, let titleID {
            if let folder = CheatLocator.folder(titleID: titleID, appURL: game.url,
                                                 home: FileManager.default.homeDirectoryForCurrentUser) {
                store = CheatStore(folder: folder, titleID: titleID, buildID: buildID,
                                   canWrite: { RunningGameMonitor.runningApplication(for: game) == nil },
                                   trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
            } else {
                status = .needsRebuild("This app's settings leave it without a cheats folder.")
            }
        }
        return CheatContext(store: store, status: status, buildID: buildID, titleID: titleID,
                            version: game.versionString)
    }

    /// Nil when the app cannot use cheats.
    func cheatState(for game: PortedGame) -> CheatState? {
        cheatState(in: cheatContext(for: game), gameID: game.id)
    }

    func cheatState(in context: CheatContext, gameID: UUID) -> CheatState? {
        guard let store = context.store else { return nil }
        let cache = Self.cheatCache
        let fingerprint = store.fingerprint()
        if let known = cache.states[gameID], known.fingerprint == fingerprint { return known.state }
        let state = store.state()
        cache.states[gameID] = (fingerprint, state)
        return state
    }

    func cheatRowValue(for game: PortedGame) -> String {
        let context = cheatContext(for: game)
        return CheatStatus.rowValue(context.status, state: cheatState(in: context, gameID: game.id))
    }

    /// The detail page's "Cheats on".
    func cheatsOn(for game: PortedGame) -> Bool {
        let context = cheatContext(for: game)
        return CheatStatus.showsDetailLabel(context.status, state: cheatState(in: context, gameID: game.id))
    }

    /// The .txt files behind what the player added: files as they are, folders searched the way the host does.
    func cheatCandidates(_ urls: [URL]) -> [(url: URL, titleIDInPath: String?)] {
        urls.flatMap { url -> [(url: URL, titleIDInPath: String?)] in
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return isFolder ? CheatInstall.candidates(in: url) : [(url, CheatInstall.titleID(inPath: url))]
        }
    }

    /// What to do with one added file. A file over the limit is refused without reading it.
    func cheatDecision(for url: URL, titleIDInPath: String?, context: CheatContext) -> CheatInstall.Decision {
        guard let buildID = context.buildID, let titleID = context.titleID else {
            return .refused("This app cannot use cheats yet.")
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= CheatFile.maxBytes else { return .refused("The file is larger than 4 MB, so it is not a cheat file.") }
        guard let data = try? Data(contentsOf: url) else { return .refused(L10n.text("NX Library could not read the file.")) }
        return CheatInstall.decide(fileName: url.lastPathComponent, data: data, titleIDInPath: titleIDInPath,
                                   buildID: buildID, titleID: titleID)
    }

    /// Diagnostics' Cheats line: counts and flags only, never names or codes.
    func cheatDiagnostics(for game: PortedGame) -> (buildID: String, filePresent: Bool, total: Int, on: Int, broken: Int,
                                                    masterOn: Bool, safeMode: Bool)? {
        let context = cheatContext(for: game)
        guard let buildID = context.buildID, let state = cheatState(in: context, gameID: game.id) else { return nil }
        let summary = state.file?.summary
        return (buildID, state.file != nil, summary?.cheats ?? 0, state.onCount, summary?.notSupported ?? 0,
                state.masterOn, state.safeModePending)
    }
}
