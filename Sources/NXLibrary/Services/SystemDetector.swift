import Foundation
import NXLibraryCore

struct ProdKeysDetectionResult {
    let path: String
    let sourceName: String
    let isValid: Bool
}

struct NxNativeDetectionResult {
    let path: String
    let isValid: Bool
}

final class SystemDetector {
    static let shared = SystemDetector()

    private init() {}

    /// Resolves the personal workspace root. The app is not tied to a bundle sibling or an external SSD.
    func resolveRootDirectory() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    /// Locates the nxnative checkout: `customDir` as it is, else the remembered folder while it exists, else
    /// `~/nxnative`. It never clones or changes it.
    func detectNxnativeDirectory(customDir: String? = nil, saved: String? = nil) -> NxNativeDetectionResult {
        let folder = customDir?.isEmpty == false
            ? URL(fileURLWithPath: customDir!)
            : EngineLocation.folder(saved: saved, home: resolveRootDirectory())
        return NxNativeDetectionResult(path: folder.path, isValid: EngineLocation.isEngine(folder))
    }

    /// Auto-detects prod.keys from Ryujinx and Switch homebrew locations (`ProdKeysLocations`).
    func detectProdKeys(additionalSearchDir: String? = nil) -> ProdKeysDetectionResult? {
        let selected = additionalSearchDir.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let fileManager = FileManager.default
        for candidate in ProdKeysLocations.candidates(home: resolveRootDirectory(), selected: selected) {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir) && !isDir.boolValue {
                if let attrs = try? fileManager.attributesOfItem(atPath: candidate.path),
                   let size = attrs[.size] as? Int64, size > 100 {
                    return ProdKeysDetectionResult(path: candidate.path, sourceName: candidate.name, isValid: true)
                }
            }
        }

        return nil
    }
}
