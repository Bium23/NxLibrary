import SwiftUI

public struct BuildExecutionSection: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isBuilding {
                    activeExecutionView
                } else if let successPath = viewModel.buildSuccessPath {
                    completedSuccessView(outputPath: successPath)
                } else if let error = viewModel.buildError {
                    failedExecutionView(errorMessage: error)
                } else if viewModel.buildState == .cancelled {
                    cancelledExecutionView
                } else {
                    idleExecutionView
                }
            }
        }
    }

    // MARK: - Active Execution

    private var activeExecutionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(viewModel.currentStageName.isEmpty
                             ? "Building..." : viewModel.currentStageName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(NXTheme.textPrimary)
                    }
                    if !viewModel.currentStepName.isEmpty {
                        Text("↳ \(viewModel.currentStepName)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(NXTheme.secondary)
                            .padding(.leading, 24)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let eta = viewModel.buildETA, eta > 0 {
                    Text("ETA \(formatted(eta))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(NXTheme.textSecondary)
                }

                Text("\(Int(viewModel.buildProgress * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(NXTheme.primary)
            }

            Group {
                if viewModel.buildProgress > 0 {
                    ProgressView(value: viewModel.buildProgress)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(NXTheme.primary)

            if !viewModel.buildStages.isEmpty {
                BuildStageStepperView(viewModel: viewModel)
            }

            HStack {
                Button(action: {
                    viewModel.showLiveLogsInBuild.toggle()
                }) {
                    Label(viewModel.showLiveLogsInBuild ? "Hide Log" : "Show Log",
                          systemImage: "terminal.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.small)

                Spacer()

                Button(action: {
                    viewModel.cancelBuild()
                }) {
                    HStack(spacing: 6) {
                        if viewModel.isCancellingBuild {
                            ProgressView().controlSize(.mini)
                            Text("Cancelling...")
                        } else {
                            Image(systemName: "stop.circle.fill")
                            Text("Cancel Build")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .tint(NXTheme.error)
                .disabled(viewModel.isCancellingBuild)
                .opacity(viewModel.isCancellingBuild ? 0.6 : 1)
            }

            if viewModel.showLiveLogsInBuild {
                BuildLiveLogsDrawer(viewModel: viewModel)
            }
        }
    }

    // MARK: - Completion

    private func completedSuccessView(outputPath: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(NXTheme.success)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Build Completed")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)
                    Text(outputPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(NXTheme.secondary)
                        .lineLimit(2)
                }
            }

            Divider().opacity(0.2)

            HStack(spacing: 10) {
                if outputPath.hasSuffix(".app") {
                    Button(action: {
                        if let game = viewModel.libraryGames.first(where: {
                            $0.url.path == outputPath
                        }) {
                            viewModel.launchGame(game)
                        } else {
                            NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
                        }
                    }) {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(NXPrimaryButtonStyle())
                }

                Button("Open Log") {
                    viewModel.openBuildLog()
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.regular)

                Button("Reveal in Finder") {
                    viewModel.openOutputInFinder()
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.regular)

                Spacer()

                Button("Build Another Game") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.resetWizard()
                    }
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.regular)
            }
        }
    }

    private func failedExecutionView(errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(NXTheme.error)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Build Failed")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.error)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(NXTheme.textSecondary)
                        .lineLimit(3)
                }
            }

            Divider().opacity(0.2)

            HStack(spacing: 10) {
                Button("Open Log") {
                    viewModel.openBuildLog()
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.regular)

                Button("Retry") {
                    viewModel.retryLastBuild()
                }
                .buttonStyle(NXPrimaryButtonStyle())
                .controlSize(.regular)

                Button("Back to Options") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.goToWizardStep(2)
                    }
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.regular)

                Spacer()

                Button("Open Console") {
                    viewModel.selectedTab = 4
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .foregroundColor(NXTheme.secondary)
            }
        }
    }

    private var cancelledExecutionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "stop.circle.fill")
                    .foregroundColor(NXTheme.warning)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Build Cancelled")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)
                    Text("The previous app was left untouched. You can open the log or retry.")
                        .font(.system(size: 12))
                        .foregroundColor(NXTheme.textSecondary)
                }
            }

            Divider().opacity(0.2)

            HStack(spacing: 10) {
                Button("Open Log") {
                    viewModel.openBuildLog()
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.regular)

                Button("Retry") {
                    viewModel.retryLastBuild()
                }
                .buttonStyle(NXPrimaryButtonStyle())
                .controlSize(.regular)

                Button("Back to Options") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.goToWizardStep(2)
                    }
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.regular)

                Spacer()
            }
        }
    }

    private var idleExecutionView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("No Build Active")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Text("Select a game and sources, then choose Add & Build.")
                    .font(.system(size: 12))
                    .foregroundColor(NXTheme.textSecondary)
            }

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.goToWizardStep(1)
                }
            }) {
                Label("Choose a Game", systemImage: "arrow.left.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(NXPrimaryButtonStyle())
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
