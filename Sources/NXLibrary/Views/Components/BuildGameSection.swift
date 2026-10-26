import SwiftUI
import NXLibraryCore

public struct BuildGameSection: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label("1. Game Sources (NSP / NSZ / XCI / XCZ)", systemImage: "gamecontroller.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)

                    if viewModel.isScanningGameFolder {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()
                }

                DropZoneView(viewModel: viewModel)

                if viewModel.selectedGameFolder != nil {
                    if viewModel.isScanningGameFolder {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Scanning sources with nxnative rules...")
                                .font(.system(size: 12))
                                .foregroundColor(NXTheme.textSecondary)
                        }
                        .padding(8)
                    } else if viewModel.detectedGames.isEmpty {
                        noFilesWarning
                    } else {
                        detectedGamesList
                        if let selected = viewModel.selectedGame {
                            sourceChecklist(for: selected)
                        }
                    }
                }

                keysStatusView
                diskStatusView
                continueRow
            }
        }
    }

    private var noFilesWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(NXTheme.warning)
            Text(viewModel.scanError
                 ?? "No readable NSP, XCI, NSZ or XCZ files were found in this folder.")
                .font(.system(size: 12))
                .foregroundColor(NXTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NXTheme.warning.opacity(0.09))
        .cornerRadius(8)
    }

    private var detectedGamesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Detected games (\(viewModel.detectedGames.count))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Spacer()
                if let selected = viewModel.selectedGame {
                    Text("\(selected.files.count) files · \(selected.formattedSize)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(NXTheme.secondary)
                }
            }

            VStack(spacing: 6) {
                ForEach(viewModel.detectedGames) { game in
                    SelectableGameCard(
                        game: game,
                        isSelected: viewModel.selectedGame?.id == game.id,
                        onSelect: {
                            guard viewModel.selectedGame?.id != game.id else { return }
                            SoundEffectService.shared.play(.click)
                            viewModel.selectedGame = game
                        }
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    private func sourceChecklist(for game: SelectableGame) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sources to include")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Spacer()
                Text("\(viewModel.selectedSources.count) of \(game.files.count) · \(viewModel.formattedSelectedSourcesSize)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(NXTheme.secondary)
            }

            if !game.hasBase {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(NXTheme.warning)
                    Text("Base required: this group has an update or DLC but no base game.")
                        .font(.system(size: 11))
                        .foregroundColor(NXTheme.warning)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NXTheme.warning.opacity(0.09))
                .cornerRadius(8)
            }

            VStack(spacing: 6) {
                ForEach(game.files) { item in
                    FileCard(
                        item: item,
                        isSelected: viewModel.selectedSourceIDs.contains(item.id),
                        isLocked: item.type == .base,
                        onToggle: { viewModel.toggleSource(item) }
                    )
                }
            }

            Text("The base game stays selected. One update can be active; DLC files can be selected individually.")
                .font(.system(size: 10))
                .foregroundColor(NXTheme.textMuted)
        }
        .padding(.top, 4)
    }

    private var keysStatusView: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.isProdKeysValid ? "key.fill" : "key.slash.fill")
                .font(.system(size: 16))
                .foregroundColor(viewModel.isProdKeysValid ? NXTheme.success : NXTheme.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isProdKeysValid ? "Keys: OK" : "Keys: missing")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                if let summary = viewModel.keySummary, viewModel.isProdKeysValid {
                    Text("header_key present · \(summary.applicationKeyGenerations.count) application key generations")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(NXTheme.textSecondary)
                } else {
                    Text("Import prod.keys once. It is copied to Application Support with 0600 permissions.")
                        .font(.system(size: 10))
                        .foregroundColor(NXTheme.textSecondary)
                }
            }

            Spacer()

            Button(viewModel.isProdKeysValid ? "Replace Key..." : "Import Key...") {
                viewModel.selectProdKeysFile()
            }
            .buttonStyle(NXSecondaryButtonStyle())
            .controlSize(.small)
        }
        .padding(9)
        .background(NXTheme.glassSurfaceElevated.opacity(0.55))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var diskStatusView: some View {
        if let available = viewModel.availableDiskBytes, viewModel.selectedSourcesSizeBytes > 0 {
            let required = viewModel.requiredBuildDiskBytes
            let availableText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let low = viewModel.isDiskSpaceLow
            HStack(spacing: 9) {
                Image(systemName: low ? "externaldrive.badge.xmark" : "externaldrive.badge.checkmark")
                    .font(.system(size: 16))
                    .foregroundColor(low ? NXTheme.warning : NXTheme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(low ? "Not enough disk space" : "Disk space ready")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(low ? NXTheme.warning : NXTheme.textPrimary)
                    Text("\(availableText) available · \(requiredText) needed (twice the sources + 10 GB)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(NXTheme.textSecondary)
                }
                Spacer()
            }
            .padding(9)
            .background((low ? NXTheme.warning : NXTheme.success).opacity(0.08))
            .cornerRadius(8)
        }
    }

    private var continueRow: some View {
        HStack {
            if let hint = continueHint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.warning)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.goToWizardStep(2)
                }
            }) {
                HStack(spacing: 8) {
                    Text("Continue to Review")
                    Image(systemName: "arrow.right.circle.fill")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .buttonStyle(NXPrimaryButtonStyle())
            .disabled(!viewModel.canAddSelectedGame)
            .opacity(viewModel.canAddSelectedGame ? 1 : 0.45)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 2)
    }

    private var continueHint: String? {
        guard let game = viewModel.selectedGame else { return nil }
        if !game.hasBase { return "Base required: add the base game before continuing." }
        if viewModel.selectedSources.isEmpty { return "Select at least the base game." }
        if viewModel.isDiskSpaceLow { return "Free disk space before continuing." }
        return nil
    }
}
