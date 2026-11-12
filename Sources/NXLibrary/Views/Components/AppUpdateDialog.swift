import SwiftUI
import NXLibraryCore

/// One dialog for manual checks, automatic offers and installation progress.
struct AppUpdateDialog: View {
    @ObservedObject var updater: AppUpdater
    let requirementNotes: [String]
    let blockedReason: String?

    private var primaryTitle: String {
        switch updater.state {
        case .available where updater.canInstallRelease: return L10n.text("Update")
        case .failed: return L10n.text("Retry")
        default: return "Close"
        }
    }
    private var title: String {
        switch updater.state {
        case .checking: return L10n.text("Checking for updates")
        case .upToDate: return L10n.text("You’re up to date")
        case .available(let release): return L10n.format("NX Library %@", [String(describing: (release.version))])
        case .downloading: return L10n.text("Downloading update")
        case .verifying: return L10n.text("Verifying update")
        case .installing: return L10n.text("Installing update")
        case .failed: return L10n.text("Update unavailable")
        default: return L10n.text("App updates")
        }
    }
    private var message: String {
        switch updater.state {
        case .checking: return L10n.text("Looking for a new release…")
        case .upToDate: return L10n.format("You have NX Library %@. No newer release is available.", [String(describing: (updater.currentVersion))])
        case .available:
            var lines = [L10n.format("You have %@.", [String(describing: (updater.currentVersion))])]
            if updater.installation == .developer {
                lines.append(L10n.text("This development copy can check releases. Install a packaged release to use automatic updates."))
            } else if updater.installation == .readOnly {
                lines.append(L10n.text("Move NX Library to Applications before updating."))
            } else if let reason = blockedReason {
                lines.append(L10n.text(reason))
            } else { lines.append(L10n.text("NX Library restarts to finish.")) }
            return (lines + requirementNotes).joined(separator: "\n\n")
        case .downloading(let progress): return L10n.format("%@%% · Download continues if you close this dialog.", [String(describing: (Int((progress * 100).rounded())))])
        case .verifying: return L10n.text("Checking the download before installing.")
        case .installing: return L10n.text("NX Library will reopen automatically.")
        case .failed(let message): return message
        case .developer: return L10n.text("This development copy can check releases but cannot replace itself.")
        case .readOnly: return L10n.text("Move NX Library to Applications before updating.")
        default: return L10n.text("Updates are currently unavailable.")
        }
    }

    var body: some View {
        SeleneConfirmDialog(title: title, message: message,
            confirmTitle: primaryTitle, cancelTitle: updater.dialogHasSecondaryButton ? L10n.text("Close") : nil,
            confirmEnabled: primaryTitle != L10n.text("Update") || blockedReason == nil,
            focus: $updater.offerFocus, onCancel: updater.later, onConfirm: updater.confirmDialog) {
                if case .checking = updater.state { ProgressView().padding(.top, 16) }
                if let release = updater.dialogRelease, !release.notes.isEmpty {
                    Text(L10n.format("Release notes · %@", [String(describing: (release.version))]))
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.top, 18)
                    SeleneDialogNotes(detail: release.notes, scrollRequest: updater.notesScroll)
                }
            }
    }
}
