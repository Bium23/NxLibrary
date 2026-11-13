import Foundation

extension CatalogScanError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceDisabled: return L10n.text("This source is disabled. Enable it in Game sources.")
        case .staleScan: return L10n.text("The source changed during the scan. Refresh it again.")
        case .wrongSourceRoot: return L10n.text("The Steam library changed while it was being checked. Refresh it again.")
        case .invalidSnapshot: return L10n.text("Steam installation data could not be verified. Your library has been kept.")
        }
    }
}

extension CatalogStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidLegacy: return L10n.text("Your previous library could not be read. The original files have been kept.")
        case .invalidCatalog(let available):
            return available
                ? L10n.text("Your library could not be read. Restore its backup or open the library folder to review the files.")
                : L10n.text("Your library could not be read. Its files have been kept. Open the library folder, then try again.")
        case .legacyChanged: return L10n.text("Another version changed your previous library. Both versions have been kept. Close the other copy and review the library folder.")
        case .staleRevision: return L10n.text("The library changed. Reload it and try again.")
        case .busy: return L10n.text("The library is busy. Try again shortly.")
        case .unsafeDirectory: return L10n.text("The library folder could not be used safely. Its files have been kept.")
        case .commitUncertain: return L10n.text("The latest save could not be confirmed. Reload the library before trying again.")
        }
    }
}

extension CatalogRepositoryError: LocalizedError {
    public var errorDescription: String? { L10n.text("That game is no longer in the library. Refresh it and try again.") }
}

extension CatalogModelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .wrongIntegration: return L10n.text("This action is not available for this game.")
        case .identityMismatch: return L10n.text("The library changed. Reload it and try again.")
        default: return L10n.text("The library contains conflicting or unsupported records. Its files have been kept.")
        }
    }
}
