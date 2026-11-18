import Foundation
@testable import NXLibraryCore

struct SettingsNotice { var retry: (() -> Void)?; var onDismiss: (() -> Void)? = nil }
final class AppViewModel {
    let catalogRepository: CatalogRepository
    var personalizations = CatalogPersonalizations.empty
    var catalogBuildRecoveries = CatalogBuildRecoveries()
    var logs: [LogEntry] = []
    var alertMessage: String?
    var settingsNotice: SettingsNotice?
    var isBuilding = false
    init(_ repository: CatalogRepository) { catalogRepository = repository }
    func reportLibrarySaveFailure(_ error: Error) { alertMessage = error.localizedDescription }
    func showSettingsNotice(title: String, message: String, actionTitle: String = "Retry", cancelTitle: String = "Back", retry: (() -> Void)? = nil) {
        settingsNotice = SettingsNotice(retry: retry)
    }
    func applyCatalog(_ document: CatalogDocument) {}
    func presentInstallFailure(for: PortedGame, error: String) {}
}
func require(_ ok: @autoclosure () -> Bool, _ message: String) throws {
    if !ok() { throw NSError(domain: "NoticeProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func run() throws {
let root = FileManager.default.temporaryDirectory.appendingPathComponent("CatalogNotice-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let store = CatalogStore(directory: root)
var catalog = try store.loadOrMigrate()
let game = PortedGame(name: "Generated fixture", url: root.appendingPathComponent("Game.app"), platform: .macApp, sizeBytes: 1, modificationDate: Date())
catalog.games = [.init(nxnative: game)]
_ = try store.save(catalog, expectedRevision: catalog.revision)
let failing = CatalogStore(directory: root, publication: .init { _, _, _, _ in throw POSIXError(.ENOSPC) })
let model = AppViewModel(CatalogRepository(store: failing))
model.reportCatalogFailure(POSIXError(.ENOSPC))
try require(model.alertMessage == nil, "Catalog failure published legacy alert and can replace its Retry notice")
try require(model.settingsNotice?.retry != nil, "Catalog reload Retry missing")
_ = model.persistBuildOutcome(game)
try require(model.alertMessage == nil, "Build failure published legacy alert and can replace its save Retry")
try require(model.settingsNotice?.retry != nil, "Build save Retry missing")
try require(model.catalogBuildRecoveries[game.id] != nil, "Build recovery missing")
// Deliver a previously queued legacy alert after the retry notice exists.
model.alertMessage = "An earlier, unrelated alert"
let host = LegacyNoticeHost(viewModel: model)
host.deliver()
try require(model.settingsNotice?.retry != nil, "Queued legacy alert replaced the structured save Retry")
try require(model.alertMessage != nil, "Queued legacy alert was lost")
host.dismiss()
try require(model.alertMessage == nil, "Deferred legacy alert was not presented after dismissal")
try require(model.settingsNotice?.retry == nil, "Expected the deferred generic notice after dismissal")
print("Actual catalog helpers and legacy bridge preserve Retry and defer unrelated alerts.")

}
do { try run() } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
