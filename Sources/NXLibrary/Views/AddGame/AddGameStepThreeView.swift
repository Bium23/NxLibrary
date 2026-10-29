import SwiftUI
import AppKit
import NXLibraryCore

struct AddGameStepThreeView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter

    @Environment(\.seleneReduceMotion) private var reduceMotion

    let focusedAction: Int
    let onActions: ([AddGameAction]) -> Void

    private struct StepAction {
        let id: String
        let title: String
        let systemImage: String?
        let kind: SeleneActionKind
        let isEnabled: Bool
        let perform: () -> Void
    }

    var body: some View {
        VStack(spacing: 18) {
            content
            actionRow
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isBuilding) { _ in publishActions() }
        .onChange(of: viewModel.isCancellingBuild) { _ in publishActions() }
        .onChange(of: viewModel.buildSuccessPath) { _ in publishActions() }
        .onChange(of: viewModel.buildError) { _ in publishActions() }
        .onChange(of: viewModel.buildState) { _ in publishActions() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isBuilding {
            buildingView
        } else if let path = viewModel.buildSuccessPath {
            successView(path: path)
        } else if let error = viewModel.buildError {
            failureView(error: error)
        } else if viewModel.buildState == .cancelled {
            cancelledView
        } else {
            idleView
        }
    }

    // MARK: - Building

    private var buildingView: some View {
        VStack(spacing: 18) {
            SelenePanel {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.currentStageName.isEmpty
                             ? "Building…" : viewModel.currentStageName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(SeleneTheme.ink)
                            .lineLimit(1)

                        Text(viewModel.currentStepName.isEmpty
                             ? "Preparing the build" : viewModel.currentStepName)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(SeleneTheme.glyph)
                            .lineLimit(1)

                        ProgressView(value: viewModel.buildProgress)
                            .progressViewStyle(.linear)
                            .tint(SeleneTheme.glyph)
                            .frame(maxWidth: 520)

                        HStack(spacing: 14) {
                            Text("Stage \(viewModel.stageIndex) of \(max(viewModel.totalStages, viewModel.buildStages.count))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(SeleneTheme.ink60)
                            if let eta = viewModel.buildETA, eta > 0 {
                                Text("ETA \(formatted(eta))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(SeleneTheme.ink60)
                            }
                        }
                    }

                    Spacer(minLength: 12)

                    Text("\(Int((viewModel.buildProgress * 100).rounded()))%")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(SeleneTheme.ink)
                        .frame(minWidth: 150, alignment: .trailing)
                }
            }

            if !viewModel.buildStages.isEmpty {
                BuildStageStepperView(viewModel: viewModel)
            }

            if viewModel.showLiveLogsInBuild {
                BuildLiveLogsDrawer(viewModel: viewModel)
            }
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Success

    private func successView(path: String) -> some View {
        SelenePanel {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(SeleneTheme.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to play")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(SeleneTheme.ink)
                    Text(path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Text("The app was installed atomically. Your library now points at the new build.")
                .font(.system(size: 10.5))
                .foregroundColor(SeleneTheme.ink90)
        }
    }

    // MARK: - Failure

    private func failureView(error: String) -> some View {
        VStack(spacing: 18) {
            SelenePanel {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(SeleneTheme.danger)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Build failed")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(SeleneTheme.ink)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(SeleneTheme.ink90)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                Text("The previous app was left untouched. The full build log has the failing command and output.")
                    .font(.system(size: 10.5))
                    .foregroundColor(SeleneTheme.ink60)
            }

            logTailPanel
        }
    }

    // MARK: - Cancelled

    private var cancelledView: some View {
        VStack(spacing: 18) {
            SelenePanel {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(SeleneTheme.untested)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Build cancelled")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(SeleneTheme.ink)
                        Text("The previous app was left untouched. You can retry or go back to the review step.")
                            .font(.system(size: 11))
                            .foregroundColor(SeleneTheme.ink90)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }

            logTailPanel
        }
    }

    private var logTailPanel: some View {
        SelenePanel("Last output") {
            VStack(alignment: .leading, spacing: 3) {
                let recent = viewModel.logs.suffix(8)
                if recent.isEmpty {
                    Text("No build output is available yet.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(SeleneTheme.ink60)
                } else {
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, entry in
                        Text(entry.message)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(logColor(entry.level))
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeleneTheme.scrim)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func logColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return SeleneTheme.ink90
        case .step: return SeleneTheme.glyph
        case .success: return SeleneTheme.success
        case .warning: return SeleneTheme.untested
        case .error: return SeleneTheme.danger
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        SelenePanel {
            HStack(spacing: 14) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 24))
                    .foregroundColor(SeleneTheme.ink60)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No build is active")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(SeleneTheme.ink)
                    Text("Go back to the review step and choose Add & Build to start a build.")
                        .font(.system(size: 11))
                        .foregroundColor(SeleneTheme.ink90)
                }
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            ForEach(actionSpecs.indices, id: \.self) { index in
                let spec = actionSpecs[index]
                SeleneActionButton(title: spec.title,
                                   systemImage: spec.systemImage,
                                   kind: spec.kind,
                                   isEnabled: spec.isEnabled,
                                   isFocused: focusedAction == index,
                                   action: spec.perform)
            }
            Spacer()
        }
    }

    private var actionSpecs: [StepAction] {
        if viewModel.isBuilding {
            return [
                StepAction(id: "log",
                           title: viewModel.showLiveLogsInBuild ? "Hide Log" : "Show Log",
                           systemImage: "terminal",
                           kind: .secondary,
                           isEnabled: true) {
                    viewModel.showLiveLogsInBuild.toggle()
                },
                StepAction(id: "cancel",
                           title: viewModel.isCancellingBuild ? "Cancelling…" : "Cancel Build",
                           systemImage: "stop.circle.fill",
                           kind: .destructive,
                           isEnabled: !viewModel.isCancellingBuild) {
                    viewModel.cancelBuild()
                },
                StepAction(id: "openLog", title: "Open Log",
                           systemImage: "doc.text.magnifyingglass",
                           kind: .secondary, isEnabled: true) {
                    viewModel.openBuildLog()
                },
                StepAction(id: "console", title: "Open Console",
                           systemImage: nil, kind: .quiet, isEnabled: true) {
                    NotificationCenter.default.post(name: .nxLibraryOpenConsole, object: nil)
                }
            ]
        }

        if let path = viewModel.buildSuccessPath {
            return [
                StepAction(id: "play", title: "Play",
                           systemImage: "play.fill", kind: .primary,
                           isEnabled: FileManager.default.fileExists(atPath: path)) {
                    play(path: path)
                },
                StepAction(id: "library", title: "Show in Library",
                           systemImage: "square.grid.2x2",
                           kind: .secondary, isEnabled: true) {
                    router.showLibrary()
                },
                StepAction(id: "another", title: "Build Another Game",
                           systemImage: "plus", kind: .secondary, isEnabled: true) {
                    withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                        viewModel.startNewAddGame()
                    }
                },
                StepAction(id: "openLog", title: "Open Log",
                           systemImage: "doc.text.magnifyingglass",
                           kind: .secondary, isEnabled: true) {
                    viewModel.openBuildLog()
                },
                StepAction(id: "reveal", title: "Reveal in Finder",
                           systemImage: "folder", kind: .secondary, isEnabled: true) {
                    viewModel.openOutputInFinder()
                }
            ]
        }

        if viewModel.buildError != nil || viewModel.buildState == .cancelled {
            return [
                StepAction(id: "retry", title: "Retry",
                           systemImage: "arrow.clockwise", kind: .primary,
                           isEnabled: !viewModel.isBuilding) {
                    viewModel.retryLastBuild()
                },
                StepAction(id: "options", title: "Back to Options",
                           systemImage: "slider.horizontal.3",
                           kind: .secondary, isEnabled: true) {
                    withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                        viewModel.goToWizardStep(2)
                    }
                },
                StepAction(id: "openLog", title: "Open Log",
                           systemImage: "doc.text.magnifyingglass",
                           kind: .secondary, isEnabled: true) {
                    viewModel.openBuildLog()
                },
                StepAction(id: "console", title: "Open Console",
                           systemImage: nil, kind: .quiet, isEnabled: true) {
                    NotificationCenter.default.post(name: .nxLibraryOpenConsole, object: nil)
                }
            ]
        }

        return [
            StepAction(id: "review", title: "Back to Review",
                       systemImage: "arrow.left", kind: .secondary,
                       isEnabled: true) {
                withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                    viewModel.goToWizardStep(viewModel.selectedGame == nil ? 1 : 2)
                }
            }
        ]
    }

    private func play(path: String) {
        if let game = viewModel.libraryGames.first(where: {
            $0.url.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
        }) {
            viewModel.launchGame(game)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func publishActions() {
        onActions(actionSpecs.map {
            AddGameAction(id: $0.id, title: $0.title,
                          isEnabled: $0.isEnabled, perform: $0.perform)
        })
    }
}
