import SwiftUI
import NXLibraryCore

public struct BuildOptionsSection: View {
    @ObservedObject public var viewModel: AppViewModel
    @State private var isAdvancedExpanded: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            SelectedGameSummaryCard(viewModel: viewModel)
            destinationCard
            sourceSummaryCard
            advancedOptionsCard
            stepNavigationFooter
        }
    }

    private var destinationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("2. Install Destination", systemImage: "arrow.down.app.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(NXTheme.primary.opacity(0.16))
                            .frame(width: 42, height: 42)
                        Image(systemName: "macbook.gen2")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(NXTheme.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS app · Apple Silicon")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(NXTheme.textPrimary)
                        Text("~/Applications/<game>.app")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(NXTheme.textSecondary)
                    }

                    Spacer()

                    Text("No DMG")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(NXTheme.glassSurfaceElevated)
                        .foregroundColor(NXTheme.textSecondary)
                        .clipShape(Capsule())
                }
                .padding(12)
                .background(NXTheme.glassSurfaceElevated.opacity(0.55))
                .cornerRadius(10)

                Text("The app is built into a temporary folder and moved into place atomically. The previous app stays untouched on failure or cancel.")
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.textSecondary)
            }
        }
    }

    private var sourceSummaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("3. Sources to Include", systemImage: "shippingbox.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)
                    Spacer()
                    Text("\(viewModel.selectedSources.count) selected · \(viewModel.formattedSelectedSourcesSize)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(NXTheme.secondary)
                }

                if let game = viewModel.selectedGame {
                    Text(game.name)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(NXTheme.textSecondary)

                    HStack(spacing: 8) {
                        sourcePill("Base", count: viewModel.selectedSources.filter { $0.type == .base }.count)
                        sourcePill("Updates", count: viewModel.selectedSources.filter { $0.type == .update }.count)
                        sourcePill("DLC", count: viewModel.selectedSources.filter { $0.type == .dlc }.count)
                    }

                    if !game.hasBase {
                        warning("Base required: this folder has an update or DLC without the base game.")
                    } else if !viewModel.selectedSources.contains(where: { $0.type == .base }) {
                        warning("The base game must stay selected.")
                    }
                } else {
                    Text("No game selected. Go back to step 1.")
                        .font(.system(size: 11))
                        .foregroundColor(NXTheme.textSecondary)
                }

                Text("The base game, newest update and all non-empty DLC are selected by default. You can change the selection in step 1.")
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.textMuted)
            }
        }
    }

    private var advancedOptionsCard: some View {
        GlassCard {
            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Application Name (Optional):")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(NXTheme.textSecondary)
                            TextField("Name displayed in macOS", text: $viewModel.appName)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(NXTheme.glassSurfaceElevated)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(NXTheme.specularRim, lineWidth: 0.8)
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bundle Identifier (Optional):")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(NXTheme.textSecondary)
                            TextField("e.g. org.nxnative.game", text: $viewModel.bundleId)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(NXTheme.glassSurfaceElevated)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(NXTheme.specularRim, lineWidth: 0.8)
                                )
                        }
                    }

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Game Language:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(NXTheme.textSecondary)
                            Picker("", selection: $viewModel.selectedLanguage) {
                                ForEach(viewModel.availableLanguages, id: \.code) { item in
                                    Text(item.label).tag(item.code)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        Spacer()
                    }

                    Text("Extracted files are always kept for fast rebuilds on macOS.")
                        .font(.system(size: 11))
                        .foregroundColor(NXTheme.textMuted)
                }
                .padding(.top, 8)
            } label: {
                Label("Advanced Options", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(NXTheme.textSecondary)
            }
        }
    }

    private var stepNavigationFooter: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.goToWizardStep(1)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.circle.fill")
                            Text("Back to Sources")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(NXSecondaryButtonStyle())

                    Spacer()

                    if viewModel.canStartBuild {
                        Button("Add to Library") {
                            viewModel.addSelectedGame(buildNow: false)
                        }
                        .buttonStyle(NXSecondaryButtonStyle())
                        .keyboardShortcut("l", modifiers: [.command])

                        Button("Add & Build") {
                            viewModel.addSelectedGame(buildNow: true)
                        }
                        .buttonStyle(NXPrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: [.command])
                    } else {
                        Button("Add & Build") {
                            viewModel.addSelectedGame(buildNow: true)
                        }
                        .buttonStyle(NXSecondaryButtonStyle())
                        .opacity(0.45)
                        .disabled(true)

                        Button("Add to Library") {
                            viewModel.addSelectedGame(buildNow: false)
                        }
                        .buttonStyle(NXPrimaryButtonStyle())
                        .disabled(!viewModel.canAddSelectedGame)
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                }

                Text(footerHint)
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.canAddSelectedGame ? NXTheme.textSecondary : NXTheme.warning)
                    .lineLimit(2)
            }
        }
    }

    private var footerHint: String {
        guard viewModel.selectedGame != nil else { return "Select a game in step 1." }
        guard let selected = viewModel.selectedGame, selected.hasBase else {
            return "Base required: add the base game NSP/XCI before adding it."
        }
        guard !viewModel.selectedSources.isEmpty else { return "Select at least the base game." }
        if viewModel.isDiskSpaceLow {
            return viewModel.diskSpaceWarningMessage ?? "Not enough free disk space."
        }
        if viewModel.canStartBuild { return "Ready to add and build." }
        if !viewModel.isProdKeysValid { return "You can add it now; import prod.keys to build it." }
        if !viewModel.isNxnativeValid { return "You can add it now; the nxnative checkout is missing." }
        if viewModel.environmentStatus?.canBuild != true {
            return "You can add it now; the build environment is incomplete."
        }
        if !viewModel.canPassToolchainGate {
            return "You can add it now; the toolchain is not certified, so building is blocked until you enable the override in Settings."
        }
        return "You can add it now."
    }

    private func sourcePill(_ title: String, count: Int) -> some View {
        Text("\(title): \(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(NXTheme.glassSurfaceElevated)
            .foregroundColor(count > 0 ? NXTheme.textPrimary : NXTheme.textMuted)
            .clipShape(Capsule())
    }

    private func warning(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(NXTheme.warning)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(NXTheme.warning)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NXTheme.warning.opacity(0.09))
        .cornerRadius(8)
    }
}
