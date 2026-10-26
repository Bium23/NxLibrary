import SwiftUI
import NXLibraryCore

public struct SelectedGameSummaryCard: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var selectedBaseCount: Int {
        viewModel.selectedSources.filter { $0.type == .base }.count
    }

    private var selectedUpdateCount: Int {
        viewModel.selectedSources.filter { $0.type == .update }.count
    }

    private var selectedDLCCount: Int {
        viewModel.selectedSources.filter { $0.type == .dlc }.count
    }

    public var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(NXTheme.primary.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 20))
                        .foregroundColor(NXTheme.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedGame?.name ?? "No Game Selected")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let game = viewModel.selectedGame {
                            Text("\(viewModel.selectedSources.count) of \(game.files.count) files")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(NXTheme.textSecondary)

                            Text(viewModel.formattedSelectedSourcesSize)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(NXTheme.secondary)

                            if selectedBaseCount == 0 {
                                Text("Base required")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(NXTheme.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(NXTheme.warning.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            if selectedUpdateCount > 0 {
                                Text("+\(selectedUpdateCount) Update\(selectedUpdateCount > 1 ? "s" : "")")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(NXTheme.secondary.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                            if selectedDLCCount > 0 {
                                Text("+\(selectedDLCCount) DLC\(selectedDLCCount > 1 ? "s" : "")")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(NXTheme.tertiary.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                Button("Change Sources") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.goToWizardStep(1)
                    }
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .font(.system(size: 11, weight: .semibold))
            }
        }
    }
}
