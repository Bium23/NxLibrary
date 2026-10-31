import Foundation
import NXLibraryCore

public struct ProdKeysDetectionResult {
    public let path: String
    public let sourceName: String
    public let isValid: Bool
}

public struct NxNativeDetectionResult {
    public let path: String
    public let isValid: Bool
}

public final class SystemDetector {
    public static let shared = SystemDetector()
    
    private init() {}
    
    /// Resolves the personal workspace root. The app is not tied to a bundle sibling or an external SSD.
    public func resolveRootDirectory() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    /// Locates the nxnative checkout: `customDir` as it is, else the remembered folder while it exists, else
    /// `~/nxnative`. It never clones or changes it.
    public func detectNxnativeDirectory(customDir: String? = nil, saved: String? = nil) -> NxNativeDetectionResult {
        let folder = customDir?.isEmpty == false
            ? URL(fileURLWithPath: customDir!)
            : EngineLocation.folder(saved: saved, home: resolveRootDirectory())
        return NxNativeDetectionResult(path: folder.path, isValid: EngineLocation.isEngine(folder))
    }

    /// Auto-detects prod.keys from Ryujinx and Switch homebrew locations (`ProdKeysLocations`).
    public func detectProdKeys(additionalSearchDir: String? = nil) -> ProdKeysDetectionResult? {
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
