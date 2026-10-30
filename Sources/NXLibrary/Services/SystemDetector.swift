import Foundation

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

    /// Locates the pinned nxnative checkout. It never clones or changes it.
    public func detectNxnativeDirectory(customDir: String? = nil) -> NxNativeDetectionResult {
        let path = (customDir?.isEmpty == false ? customDir! : NSString(string: "~/nxnative").expandingTildeInPath)
        let scriptPath = URL(fileURLWithPath: path).appendingPathComponent("scripts/build_ipa_from_nsp.py").path
        let dmPath = URL(fileURLWithPath: path).appendingPathComponent("dm").path
        let valid = FileManager.default.fileExists(atPath: scriptPath)
            && FileManager.default.fileExists(atPath: dmPath)
        return NxNativeDetectionResult(path: path, isValid: valid)
    }

    /// Auto-detects prod.keys from Ryujinx and Switch homebrew locations
    public func detectProdKeys(additionalSearchDir: String? = nil) -> ProdKeysDetectionResult? {
        var candidateLocations: [(path: String, name: String)] = [
            (
                NSString(string: "~/Library/Application Support/Ryujinx/system/prod.keys").expandingTildeInPath,
                "Ryujinx (App Support)"
            ),
            (
                NSString(string: "~/Library/Application Support/ryujinx/system/prod.keys").expandingTildeInPath,
                "Ryujinx (App Support)"
            )
        ]
        
        let root = resolveRootDirectory()
        let siblingCandidates = [
            root.deletingLastPathComponent().appendingPathComponent("Riujinx/system/prod.keys").path,
            root.deletingLastPathComponent().appendingPathComponent("Riujinx/ProdKeys.Net-21.2.0/prod.keys").path,
            root.appendingPathComponent("Riujinx/system/prod.keys").path
        ]
        
        for p in siblingCandidates {
            candidateLocations.append((p, "Ryujinx Folder"))
        }
        
        if let customDir = additionalSearchDir, !customDir.isEmpty {
            let direct = URL(fileURLWithPath: customDir).appendingPathComponent("prod.keys").path
            let systemSub = URL(fileURLWithPath: customDir).appendingPathComponent("system/prod.keys").path
            candidateLocations.insert((direct, "Selected Directory"), at: 0)
            candidateLocations.insert((systemSub, "Selected Directory/system"), at: 0)
        }
        
        candidateLocations.append((
            NSString(string: "~/.switch/prod.keys").expandingTildeInPath,
            "Switch Homebrew"
        ))
        
        let fileManager = FileManager.default
        for candidate in candidateLocations {
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
