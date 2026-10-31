import Foundation
import NXLibraryCore

extension AppViewModel {
    /// What the compatibility gate says now; nil until the first check has run.
    var toolchainGateSummary: ToolchainGateCopy.Summary? {
        compatibilityReport.map { ToolchainGateCopy.summary(report: $0, overrideOn: allowUntestedToolchain) }
    }
}
