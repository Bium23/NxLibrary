import SwiftUI
import NXLibraryCore

/// One dialog for manual checks, automatic offers and installation progress.
struct AppUpdateDialog: View {
    @ObservedObject var updater: AppUpdater
    let requirementNotes: [String]
    let blockedReason: String?

    private var primaryTitle: String {
        switch updater.state {
        case .available where updater.canInstallRelease: return "Update"
        case .failed: return "Retry"
        default: return "Close"
        }
    }
    private var title: String {
        switch updater.state {
        case .checking: return "Checking for updates"
        case .upToDate: return "You’re up to date"
        case .available(let release): return "NX Library \(release.version)"
        case .downloading: return "Downloading update"
        case .verifying: return "Verifying update"
        case .installing: return "Installing update"
        case .failed: return "Update unavailable"
        default: return "App updates"
        }
    }
    private var message: String {
        switch updater.state {
        case .checking: return "Looking for a new release…"
        case .upToDate: return "You have NX Library \(updater.currentVersion). No newer release is available."
        case .available:
            var lines = ["You have \(updater.currentVersion)."]
            if updater.installation == .developer {
                lines.append("This development copy can check releases. Install a packaged release to use automatic updates.")
            } else if updater.installation == .readOnly {
                lines.append("Move NX Library to Applications before updating.")
            } else if let reason = blockedReason {
                lines.append("The update can install \(reason.prefix(1).lowercased() + reason.dropFirst()).")
            } else { lines.append("NX Library restarts to finish.") }
            return (lines + requirementNotes).joined(separator: "\n\n")
        case .downloading(let progress): return "\(Int((progress * 100).rounded()))% · Download continues if you close this dialog."
        case .verifying: return "Checking the download before installing."
        case .installing: return "NX Library will reopen automatically."
        case .failed(let message): return message
        case .developer: return "This development copy can check releases but cannot replace itself."
        case .readOnly: return "Move NX Library to Applications before updating."
        default: return "Updates are currently unavailable."
        }
    }

    var body: some View {
        SeleneConfirmDialog(title: title, message: message,
            confirmTitle: primaryTitle, cancelTitle: updater.dialogHasSecondaryButton ? "Close" : nil,
            confirmEnabled: primaryTitle != "Update" || blockedReason == nil,
            focus: $updater.offerFocus, onCancel: updater.later, onConfirm: updater.confirmDialog) {
                if case .checking = updater.state { ProgressView().padding(.top, 16) }
                if let release = updater.dialogRelease, !release.notes.isEmpty {
                    Text("Release notes · \(release.version)")
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.top, 18)
                    SeleneDialogNotes(detail: release.notes, scrollRequest: updater.notesScroll)
                }
            }
    }
}
