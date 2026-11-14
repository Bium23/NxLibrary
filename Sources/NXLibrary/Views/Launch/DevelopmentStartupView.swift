import AppKit
import SwiftUI
import NXLibraryCore
import os

@MainActor
final class DevelopmentStartup: ObservableObject {
    @Published private(set) var shell: AppShellState?
    @Published private(set) var failure: String?
    @Published private(set) var working = false
    @Published private(set) var recovery: CatalogRecoveryCandidate?
    private let logger = Logger(subsystem: "local.nxlibrary", category: "Startup")

    func prepare() async {
        guard shell == nil, !working else { return }
        working = true
        failure = nil
        recovery = nil
        var profileReady = false
        do {
            // Services and SwiftUI StateObjects are created only after the profile transaction finishes.
            if AppData.profile.isDevelopment,
               NSRunningApplication.runningApplications(withBundleIdentifier: "local.nxlibrary")
                .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                throw DevelopmentStartupFailure.otherCopyRunning
            }
            try await Task.detached(priority: .userInitiated) { try AppData.prepare() }.value
            profileReady = true
            let catalog = try await Task.detached(priority: .userInitiated) {
                try CatalogStore(directory: AppData.supportRoot).loadOrMigrate()
            }.value
            logger.notice("Launcher data ready; preparing shell models")
            let store = AppSettingsStore()
            // Complete model/AppKit startup outside the render that inserts MainView.
            shell = AppShellState(settings: store, catalog: catalog, repository: CatalogRepository(store: CatalogStore(directory: AppData.supportRoot)))
            logger.notice("Shell models ready")
        } catch {
            logger.error("Launcher preparation failed")
            failure = error.localizedDescription
            if profileReady {
                recovery = try? await Task.detached(priority: .userInitiated) {
                    try CatalogStore(directory: AppData.supportRoot).recoveryCandidate()
                }.value
            }
        }
        working = false
    }

    func restoreBackup() async {
        guard !working, let candidate = recovery else { return }
        working = true
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try CatalogStore(directory: AppData.supportRoot).restoreBackup(candidate)
            }.value
            working = false
            await prepare()
        } catch {
            failure = error.localizedDescription
            recovery = nil
            working = false
        }
    }

}

private enum DevelopmentStartupFailure: LocalizedError {
    case otherCopyRunning
    var errorDescription: String? {
        L10n.text("Close the other NX Library copy, then try again. Your original library has not been changed.", context: AppLocale(language: .automatic, region: nil))
    }
}

/// Bootstrap has no app stores, themes or game-operation hooks until its profile is ready.
struct DevelopmentStartupView: View {
    @StateObject private var startup = DevelopmentStartup()
    private let context = AppLocale(language: .automatic, region: nil)
    var body: some View {
        Group {
            if let shell = startup.shell {
                MainView(state: shell)
                    .onAppear {
                        Logger(subsystem: "local.nxlibrary", category: "Startup").notice("Library view appeared")
                    }
            } else {
                VStack(spacing: 20) {
                    if startup.working { ProgressView().controlSize(.large) }
                    Text(L10n.text(startup.failure == nil ? "Preparing your library" : "Library unavailable", context: context))
                        .font(.system(size: 28, weight: .semibold))
                    Text(startup.failure ?? L10n.text("Preparing a separate copy of your launcher data. Games stay in their current locations.", context: context))
                        .font(.system(size: 17)).multilineTextAlignment(.center)
                    if startup.failure != nil {
                        if let candidate = startup.recovery {
                            Button(L10n.count("Restore backup (%lld games)", candidate.gameCount, context: context)) {
                                Task { await startup.restoreBackup() }
                            }.keyboardShortcut("r", modifiers: [.command, .shift])
                                .disabled(startup.working)
                        }
                        HStack(spacing: 24) {
                            Button(L10n.text("Close", context: context)) { NSApplication.shared.terminate(nil) }
                                .keyboardShortcut(.cancelAction)
                            Button(L10n.text("Open library folder", context: context)) { NSWorkspace.shared.open(AppData.supportRoot) }
                                .keyboardShortcut("o", modifiers: [.command])
                            Button(L10n.text("Retry", context: context)) { Task { await startup.prepare() } }
                                .keyboardShortcut(.defaultAction)
                        }.disabled(startup.working)
                    }
                }
                .foregroundColor(.white)
                .padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            }
        }
        .task { await startup.prepare() }
    }
}
