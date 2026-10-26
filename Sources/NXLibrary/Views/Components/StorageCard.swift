import SwiftUI
import NXLibraryCore

public struct StorageCard: View {
    @ObservedObject public var viewModel: AppViewModel
    @State private var cleanupToConfirm: CleanupKind?
    @State private var backupGameID: UUID?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private enum CleanupKind: String, Identifiable {
        case caches, logs
        var id: String { rawValue }
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Storage & Cleanup", systemImage: "externaldrive.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)

                    Spacer()

                    if viewModel.isCalculatingStorage {
                        ProgressView().controlSize(.small)
                    }

                    Button("Recalculate") {
                        viewModel.refreshStorageUsage()
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(viewModel.isCalculatingStorage)
                }

                if let usage = viewModel.storageUsage {
                    VStack(spacing: 6) {
                        usageRow("Library apps", bytes: usage.libraryBytes)
                        usageRow("Build caches", bytes: usage.cacheBytes)
                        usageRow("Logs", bytes: usage.logsBytes)
                        usageRow("Free on volume", bytes: usage.freeBytes, positive: true)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Calculating storage...")
                            .font(.system(size: 11))
                            .foregroundColor(NXTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }

                Divider().opacity(0.2)

                HStack(spacing: 8) {
                    Button("Delete Caches") {
                        cleanupToConfirm = .caches
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(viewModel.isBuilding)

                    Button("Delete Logs") {
                        cleanupToConfirm = .logs
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(viewModel.isBuilding)

                    Spacer()
                }

                if viewModel.isBuilding {
                    Text("Available after the active build finishes or is cancelled.")
                        .font(.system(size: 10))
                        .foregroundColor(NXTheme.warning)
                }

                Text("Cleanup only removes build caches and logs. Apps and source files are never deleted here.")
                    .font(.system(size: 10))
                    .foregroundColor(NXTheme.textMuted)

                Divider().opacity(0.2)

                HStack(spacing: 8) {
                    Text("Save backup")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(NXTheme.textPrimary)

                    Picker("", selection: $backupGameID) {
                        Text("Select a game").tag(nil as UUID?)
                        ForEach(viewModel.libraryGames) { game in
                            Text(game.name).tag(game.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)

                    Button("Back Up Save...") {
                        if let id = backupGameID,
                           let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                            viewModel.backupSave(for: game)
                        }
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(backupGameID == nil)

                    Spacer()
                }
            }
        }
        .onAppear {
            if backupGameID == nil { backupGameID = viewModel.libraryGames.first?.id }
            viewModel.refreshStorageUsage()
        }
        .confirmationDialog(cleanupTitle, isPresented: cleanupBinding,
                            titleVisibility: .visible) {
            Button(cleanupButton, role: .destructive) {
                switch cleanupToConfirm {
                case .caches: viewModel.deleteCaches()
                case .logs: viewModel.deleteLogs()
                case nil: break
                }
                cleanupToConfirm = nil
            }
            Button("Cancel", role: .cancel) { cleanupToConfirm = nil }
        } message: {
            Text(cleanupMessage)
        }
    }

    private var cleanupBinding: Binding<Bool> {
        Binding(
            get: { cleanupToConfirm != nil },
            set: { if !$0 { cleanupToConfirm = nil } }
        )
    }

    private var cleanupTitle: String {
        cleanupToConfirm == .logs ? "Delete build and runtime logs?" : "Delete build caches?"
    }

    private var cleanupButton: String {
        cleanupToConfirm == .logs ? "Delete Logs" : "Delete Caches"
    }

    private var cleanupMessage: String {
        if cleanupToConfirm == .logs {
            return "This removes the logs for every library game. It does not touch saves, apps or sources."
        }
        return "This removes the extracted build caches for every library game. A future build will extract the sources again."
    }

    private func usageRow(_ title: String, bytes: Int64, positive: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(NXTheme.textSecondary)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(positive ? NXTheme.success : NXTheme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(NXTheme.glassSurfaceElevated.opacity(0.45))
        .cornerRadius(6)
    }
}
