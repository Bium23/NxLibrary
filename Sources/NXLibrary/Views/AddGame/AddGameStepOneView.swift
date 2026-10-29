import SwiftUI
import NXLibraryCore

struct AddGameStepOneView: View {
    @ObservedObject var viewModel: AppViewModel

    @Environment(\.seleneReduceMotion) private var reduceMotion

    let focusedAction: Int
    let onActions: ([AddGameAction]) -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 18) {
                SelenePanel {
                    DropZoneView(viewModel: viewModel, isFocused: focusedAction == 0)
                }
                sourcesPanel
                if let scanError = viewModel.scanError {
                    warningPanel(title: "Could not read this folder",
                                 message: scanError)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                destinationPanel
                selectedPanel
                keyStatus
                if viewModel.isDiskSpaceLow, let message = viewModel.diskSpaceWarningMessage {
                    warningPanel(title: "Not enough disk space", message: message)
                }
                actionRow
            }
            .frame(width: 360)
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.canAddSelectedGame) { _ in publishActions() }
    }

    // MARK: - Sources

    private var sourcesPanel: some View {
        SelenePanel {
            HStack(alignment: .firstTextBaseline) {
                Text("Selected sources")
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Spacer()
                Text("\(viewModel.selectedSources.count) · \(viewModel.formattedSelectedSourcesSize)")
                    .seleneFont(13, .semibold, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
            }

            if viewModel.selectedGameFolder == nil {
                Text("Choose a folder or drop game files above to begin.")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.isScanningGameFolder {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning sources with nxnative rules…")
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink90)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.detectedGames.isEmpty {
                Text("No games were detected in this folder.")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 7) {
                    ForEach(viewModel.detectedGames) { game in
                        gameRow(game)
                    }
                }

                if let game = viewModel.selectedGame {
                    Divider().overlay(SeleneTheme.ink15)

                    HStack {
                        Text("Sources to include")
                            .seleneFont(15, .semibold)
                            .foregroundColor(SeleneTheme.ink90)
                        Spacer()
                        Text("\(viewModel.selectedSources.count) of \(game.files.count)")
                            .seleneFont(13, .regular, design: .monospaced)
                            .foregroundColor(SeleneTheme.ink60)
                    }

                    if !game.hasBase {
                        warningPanel(title: "Base game required",
                                     message: "This group has an update or DLC but no base game. Add the base NSP/XCI to build it.")
                    }

                    VStack(spacing: 6) {
                        ForEach(game.files) { item in
                            sourceRow(item)
                        }
                    }

                    Text("The base game stays selected. One update can be active; DLC files can be selected individually. Use the pointer or Tab for these checkboxes.")
                        .seleneFont(13)
                        .foregroundColor(SeleneTheme.ink60)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func gameRow(_ game: SelectableGame) -> some View {
        let isSelected = viewModel.selectedGame?.id == game.id
        return Button {
            guard viewModel.selectedGame?.id != game.id else { return }
            SoundEffectService.shared.play(.click)
            viewModel.selectedGame = game
        } label: {
            SeleneRow(game.name, subtitle: gameSubtitle(game)) {
                HStack(spacing: 10) {
                    Text(game.formattedSize)
                        .seleneFont(13, .semibold, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink60)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .seleneFont(19, .semibold)
                        .foregroundColor(isSelected ? SeleneTheme.glyph : SeleneTheme.ink.opacity(0.25))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous)
                    .strokeBorder(isSelected ? SeleneTheme.glyph.opacity(0.65) : Color.clear,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(game.name), \(game.summaryText)")
    }

    private func sourceRow(_ item: GameFileItem) -> some View {
        let isSelected = viewModel.selectedSourceIDs.contains(item.id)
        let isLocked = item.type == .base
        return SeleneRow(item.name, subtitle: sourceSubtitle(item)) {
            HStack(spacing: 10) {
                sourceBadge(item.type)
                Toggle("", isOn: Binding(
                    get: { viewModel.selectedSourceIDs.contains(item.id) },
                    set: { newValue in
                        let current = viewModel.selectedSourceIDs.contains(item.id)
                        if newValue != current { viewModel.toggleSource(item) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(SeleneToggleStyle())
                .disabled(isLocked)
                .opacity(isLocked ? 0.55 : 1)
                .accessibilityLabel("Include \(item.name)")
            }
        }
        .opacity(isSelected ? 1 : 0.62)
    }

    private func gameSubtitle(_ game: SelectableGame) -> String {
        var parts: [String] = []
        if let version = versionLabel(game.newestUpdate) {
            parts.append(version)
        }
        if let titleId = game.titleId, !titleId.isEmpty {
            parts.append(titleId)
        }
        parts.append(game.summaryText)
        return parts.joined(separator: " · ")
    }

    private func sourceSubtitle(_ item: GameFileItem) -> String {
        var parts: [String] = []
        if let version = versionLabel(item) { parts.append(version) }
        parts.append(item.formattedSize)
        if let titleId = item.titleId, !titleId.isEmpty { parts.append(titleId) }
        return parts.joined(separator: " · ")
    }

    private func versionLabel(_ item: GameFileItem?) -> String? {
        guard let raw = item?.versionString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw.lowercased().hasPrefix("v") ? raw : "v\(raw)"
    }

    private func sourceBadge(_ type: SourceKind) -> some View {
        let color: Color
        switch type {
        case .base: color = SeleneTheme.glyph
        case .update: color = SeleneTheme.untested
        case .dlc: color = SeleneTheme.success
        case .unknown: color = SeleneTheme.ink60
        }
        return Text(type.title.uppercased())
            .seleneFont(11, .bold)
            .tracking(0.8)
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .overlay(Capsule().strokeBorder(color.opacity(0.24), lineWidth: 1))
            .clipShape(Capsule())
    }

    // MARK: - Destination and summary

    private var destinationPanel: some View {
        SelenePanel("Destination") {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SeleneTheme.ink.opacity(0.06))
                        .frame(width: 38, height: 38)
                    Image(systemName: "macbook.gen2")
                        .seleneFont(19, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("macOS app · Apple Silicon")
                        .seleneFont(16, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.94))
                    Text(destinationPath)
                        .seleneFont(13, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("No DMG")
                    .seleneFont(11, .bold)
                    .tracking(0.6)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SeleneTheme.ink.opacity(0.05))
                    .overlay(Capsule().strokeBorder(SeleneTheme.ink15, lineWidth: 1))
                    .clipShape(Capsule())
            }

            Text("The app is written to a temporary folder and moved into place atomically. The previous app stays untouched on failure or cancel.")
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink60)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedPanel: some View {
        SelenePanel("Selected") {
            if let game = viewModel.selectedGame {
                Text(game.name)
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink.opacity(0.94))
                    .lineLimit(1)

                sourceCountRow("Base", count: selectedCount(.base))
                sourceCountRow("Updates", count: selectedCount(.update))
                sourceCountRow("DLC", count: selectedCount(.dlc))

                Divider().overlay(SeleneTheme.ink15)

                HStack {
                    Text("Total size")
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink90)
                    Spacer()
                    Text(viewModel.formattedSelectedSourcesSize)
                        .seleneFont(15, .semibold, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink)
                }
            } else {
                Text("No game selected yet.")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
            }

            Text("The base game, newest update and all non-empty DLC are selected by default.")
                .seleneFont(13)
                .foregroundColor(SeleneTheme.ink60)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectedCount(_ kind: SourceKind) -> Int {
        viewModel.selectedSources.filter { $0.type == kind }.count
    }

    private func sourceCountRow(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .seleneFont(15)
                .foregroundColor(SeleneTheme.ink90)
            Spacer()
            Text("\(count)")
                .seleneFont(15, .semibold, design: .monospaced)
                .foregroundColor(count > 0 ? SeleneTheme.ink : SeleneTheme.ink60)
        }
    }

    private var destinationPath: String {
        AddGameDestination.path(appName: viewModel.appName,
                                gameName: viewModel.selectedGame?.name)
    }

    // MARK: - Status

    @ViewBuilder
    private var keyStatus: some View {
        if viewModel.isProdKeysValid {
            HStack(spacing: 9) {
                Image(systemName: "key.fill")
                    .seleneFont(19)
                    .foregroundColor(SeleneTheme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keys ready")
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.94))
                    if let summary = viewModel.keySummary {
                        Text("\(summary.applicationKeyGenerations.count) application key generations")
                            .seleneFont(13, .regular, design: .monospaced)
                            .foregroundColor(SeleneTheme.ink60)
                    }
                }
                Spacer()
                Button("Replace key…") { viewModel.selectProdKeysFile() }
                    .buttonStyle(.plain)
                    .seleneFont(13, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
            }
            .padding(.horizontal, 2)
        } else {
            warningPanel(title: "prod.keys is missing",
                         message: "Import prod.keys once. It is copied to Application Support with 0600 permissions.",
                         actionTitle: "Import key…") {
                viewModel.selectProdKeysFile()
            }
        }
    }

    private func warningPanel(title: String, message: String,
                              actionTitle: String? = nil,
                              action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .seleneFont(16)
                .foregroundColor(SeleneTheme.untested)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.untested)
                Text(message)
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .seleneFont(13, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeleneTheme.untested.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous)
                .strokeBorder(SeleneTheme.untested.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous))
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            SeleneActionButton(title: "Back", kind: .secondary,
                               isFocused: focusedAction == 1,
                               action: onClose)
            Spacer()
            SeleneActionButton(title: "Continue", systemImage: "arrow.right",
                               kind: .primary,
                               isEnabled: viewModel.canAddSelectedGame,
                               isFocused: focusedAction == 2,
                               action: goNext)
        }
    }

    private func goNext() {
        guard viewModel.canAddSelectedGame else { return }
        withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
            viewModel.goToWizardStep(2)
        }
    }

    private func publishActions() {
        onActions([
            .init(id: "choose", title: "Choose folder") {
                viewModel.selectGameFolder()
            },
            .init(id: "back", title: "Back", perform: onClose),
            .init(id: "continue", title: "Continue",
                  isEnabled: viewModel.canAddSelectedGame,
                  perform: goNext)
        ])
    }
}
