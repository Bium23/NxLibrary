import Foundation
import NXLibraryCore

/// The imported prod.keys against the selected sources, before a porting (`KeyCheck`).
extension AppViewModel {
    /// Keys that are too old or do not open the game disable Add and port.
    var keyCheckBlocks: Bool { keyCheck?.blocks == true }

    /// Re-runs the check off the main thread when the keys file or the selected sources changed;
    /// a result that arrives after a newer change is dropped.
    func refreshKeyCheck() {
        let sources = selectedSources
        let files = KeyCheck.parts(sources.map { ($0.kind, $0.url) })
        guard SourceSelection.requiresKeys(sources), isProdKeysValid, !files.isEmpty else {
            keyCheck = nil
            keyCheckToken = nil
            return
        }
        let keysURL = keyStore.keyURL
        let modified = (try? FileManager.default.attributesOfItem(atPath: keysURL.path)[.modificationDate]) as? Date
        let token = ([String(modified?.timeIntervalSince1970 ?? 0)]
            + sources.map { "\($0.url.path)|\($0.sizeBytes)" }.sorted()).joined(separator: "\n")
        guard token != keyCheckToken else { return }
        keyCheckToken = token
        keyCheck = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = KeyCheck.run(keysURL: keysURL, files: files)
            guard let self else { return }
            await MainActor.run {
                guard self.keyCheckToken == token else { return }
                self.keyCheck = outcome
            }
        }
    }
}
