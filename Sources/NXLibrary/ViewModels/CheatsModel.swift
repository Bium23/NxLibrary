import AppKit
import NXLibraryCore
import ArcanePorting

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
/// not running. It publishes nothing: the Cheats panel, the Game options row and the game page read it when they
/// open or reload. Whether the app's engine has cheats is git's answer, which `prepare(for:)` asks off the main
/// thread; until it is kept, `cheatContext(for:)` is nil and every reader says nothing about cheats.
/// It reaches the rest of Arcane only through `app`, for the engine folder.
final class CheatsModel {
    /// The coordinator; cheats read only the engine folder from the Setup.
    unowned let app: AppViewModel

    init(app: AppViewModel) {
        self.app = app
    }

    /// Engine ancestry answers and states read from disk, per launch of Arcane. The state is read again whenever
    /// the files' fingerprint changes, so the panel, the host and a hand edit are all seen.
    private final class CheatCache {
        var ancestry: (path: String, value: EngineAncestry)?
        var states: [UUID: (fingerprint: [String], state: CheatState)] = [:]
    }

    private static let cheatCache = CheatCache()

    private func engineAncestry() -> EngineAncestry {
        let cache = Self.cheatCache
        if let known = cache.ancestry, known.path == app.setup.nxnativePath { return known.value }
        let value = EngineAncestry(runner: SystemCommandRunner(), engineFolder: URL(fileURLWithPath: app.setup.nxnativePath))
        cache.ancestry = (app.setup.nxnativePath, value)
        return value
    }

    /// An imported app has no build record: the commit its packer wrote says which engine it carries.
    private func engineCommit(of game: PortedGame) -> String? {
        CheatLocator.engineCommit(appURL: game.url, recorded: game.lastBuild?.engineCommit)
    }

    /// Asks git, off the main thread, whether the game's engine has cheats, and keeps the answer for this launch.
    @MainActor
    func prepare(for game: PortedGame) async {
        guard let commit = engineCommit(of: game) else { return }
        _ = await engineAncestry().answer(CheatStatus.cheatsCommit, in: commit)
    }

    /// Nil while the status needs git's answer and `prepare(for:)` has not kept it yet; never runs git.
    func cheatContext(for game: PortedGame) -> CheatContext? {
        let buildID = CheatLocator.buildID(appURL: game.url)
        let titleID = CheatLocator.titleID(appURL: game.url, fallback: game.titleId)
        let ancestry = engineAncestry()
        var waiting = false
        var status = CheatStatus.of(engineCommit: engineCommit(of: game), buildID: buildID, titleID: titleID,
                                    isAncestor: { commit in
                                        guard let kept = ancestry.keptAnswer(CheatStatus.cheatsCommit, in: commit) else {
                                            waiting = true
                                            return nil
                                        }
                                        return kept
                                    })
        if waiting { return nil }
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

    func cheatState(in context: CheatContext, gameID: UUID) -> CheatState? {
        guard let store = context.store else { return nil }
        let cache = Self.cheatCache
        let fingerprint = store.fingerprint()
        if let known = cache.states[gameID], known.fingerprint == fingerprint { return known.state }
        let state = store.state()
        cache.states[gameID] = (fingerprint, state)
        return state
    }

    /// Nil until the engine's answer is kept.
    func cheatRowValue(for game: PortedGame) -> String? {
        guard let context = cheatContext(for: game) else { return nil }
        return CheatStatus.rowValue(context.status, state: cheatState(in: context, gameID: game.id))
    }

    /// The detail page's "Cheats on"; false until the engine's answer is kept.
    func cheatsOn(for game: PortedGame) -> Bool {
        guard let context = cheatContext(for: game) else { return false }
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
        guard let data = try? Data(contentsOf: url) else { return .refused(L10n.text("Arcane could not read the file.")) }
        return CheatInstall.decide(fileName: url.lastPathComponent, data: data, titleIDInPath: titleIDInPath,
                                   buildID: buildID, titleID: titleID)
    }

    /// Diagnostics' Cheats line: counts and flags only, never names or codes.
    func cheatDiagnostics(for game: PortedGame) -> (buildID: String, filePresent: Bool, total: Int, on: Int, broken: Int,
                                                    masterOn: Bool, safeMode: Bool)? {
        guard let context = cheatContext(for: game), let buildID = context.buildID, let state = cheatState(in: context, gameID: game.id) else { return nil }
        let summary = state.file?.summary
        return (buildID, state.file != nil, summary?.cheats ?? 0, state.onCount, summary?.notSupported ?? 0,
                state.masterOn, state.safeModePending)
    }
}
