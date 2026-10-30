import SwiftUI
import AppKit
import NXLibraryCore

struct AddGameStepThreeView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    var artwork: ArtworkStore? = nil

    @Environment(\.seleneCanvas) private var canvas

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
        VStack(alignment: .leading, spacing: canvas.u(24)) {
            HStack(alignment: .top, spacing: canvas.u(36)) {
                portingTile
                stageList
            }
            PortingLogBox(logs: viewModel.logs, expanded: $viewModel.showLiveLogsInBuild)
        }
    }

    /// The game being ported, as its tile looks on the home, with the time left.
    @ViewBuilder private var portingTile: some View {
        let side = canvas.u(220)
        VStack(spacing: canvas.u(14)) {
            if let game = portingGame {
                Group {
                    if let artwork {
                        SpotlightTileArtwork(game: game, side: side, artwork: artwork, ownIconFirst: true)
                    } else {
                        Image(nsImage: GameIconProvider.squareArt(for: game) ?? GameIconProvider.icon(for: game))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .portingLook(viewModel.portingTileLook(game), cornerRadius: canvas.u(18))
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: canvas.u(18), style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: canvas.u(12))
                Text(game.name)
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Text(viewModel.portingETAText ?? (viewModel.currentStageName.isEmpty ? "Preparing" : viewModel.currentStageName))
                .seleneFont(15)
                .foregroundColor(SeleneTheme.ink60)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: canvas.u(240))
    }

    private var portingGame: PortedGame? {
        let id = viewModel.currentBuildGameID ?? viewModel.lastBuildGameID
        return viewModel.libraryGames.first { $0.id == id }
    }

    /// Compact stage rows: check, spinner or cross, the name and the time it took.
    private var stageList: some View {
        VStack(alignment: .leading, spacing: canvas.u(4)) {
            if viewModel.buildStages.isEmpty {
                Text("Starting the porting…")
                    .seleneFont(17)
                    .foregroundColor(SeleneTheme.ink60)
            }
            ForEach(viewModel.buildStages) { stage in
                HStack(spacing: canvas.u(12)) {
                    stageMark(stage)
                        .frame(width: canvas.u(22), height: canvas.u(22))
                    VStack(alignment: .leading, spacing: canvas.u(2)) {
                        Text(stage.name.prefix(1).uppercased() + stage.name.dropFirst())
                            .seleneFont(17, stage.isRunning ? .semibold : .regular)
                            .foregroundColor(stage.isRunning ? SeleneTheme.ink : SeleneTheme.ink75)
                        if stage.isRunning, !viewModel.currentStepName.isEmpty {
                            Text(viewModel.currentStepName)
                                .seleneFont(13, .regular, design: .monospaced)
                                .foregroundColor(SeleneTheme.ink60)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: canvas.u(12))
                    if let elapsed = stage.elapsedSeconds {
                        Text(elapsedText(elapsed))
                            .seleneFont(14, .regular, design: .monospaced)
                            .foregroundColor(SeleneTheme.ink60)
                    }
                }
                .padding(.horizontal, canvas.u(16))
                .frame(minHeight: canvas.u(46))
                .background(
                    RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous)
                        .fill(stage.isRunning ? SeleneTheme.glass : Color.clear)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: viewModel.buildStages)
    }

    @ViewBuilder private func stageMark(_ stage: BuildStageItem) -> some View {
        if stage.isFailed {
            Image(systemName: "xmark")
                .seleneFont(14, .bold)
                .foregroundColor(PortingPillCopy.softRed)
        } else if stage.isRunning {
            ProgressView()
                .controlSize(.small)
                .tint(SeleneTheme.ink)
        } else {
            Image(systemName: "checkmark")
                .seleneFont(14, .bold)
                .foregroundColor(PortingLogBox.softGreen)
        }
    }

    private func elapsedText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        return String(format: "%d:%02d", total / 60, total % 60)
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
                    .seleneFont(34)
                    .foregroundColor(SeleneTheme.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to play")
                        .seleneFont(34, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                    Text(path)
                        .seleneFont(14, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Text("The app was installed atomically. Your library now points at the new build.")
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink90)
        }
    }

    // MARK: - Failure

    private func failureView(error: String) -> some View {
        VStack(spacing: 18) {
            SelenePanel {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "xmark.circle.fill")
                        .seleneFont(34)
                        .foregroundColor(PortingPillCopy.softRed)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Porting failed")
                            .seleneFont(34, .semibold)
                            .foregroundColor(SeleneTheme.ink)
                        Text(error)
                            .seleneFont(15)
                            .foregroundColor(SeleneTheme.ink90)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                Text("The previous app was left untouched. The full build log has the failing command and output.")
                    .seleneFont(14)
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
                        .seleneFont(34)
                        .foregroundColor(SeleneTheme.untested)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Porting cancelled")
                            .seleneFont(34, .semibold)
                            .foregroundColor(SeleneTheme.ink)
                        Text("The previous app was left untouched. You can retry or go back to the review step.")
                            .seleneFont(15)
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
        PortingLogBox(logs: viewModel.logs, expanded: $viewModel.showLiveLogsInBuild)
    }

    // MARK: - Idle

    private var idleView: some View {
        SelenePanel {
            HStack(spacing: 14) {
                Image(systemName: "hammer.fill")
                    .seleneFont(34)
                    .foregroundColor(SeleneTheme.ink60)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No build is active")
                        .seleneFont(19, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                    Text("Go back to the review step and choose Add & Build to start a build.")
                        .seleneFont(15)
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
                           title: viewModel.isCancellingBuild ? "Cancelling…" : "Cancel porting",
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

/// The porting's log in a collapsible glass box: small monospaced lines in ink60,
/// errors in soft red, successes in soft green, following the newest line and
/// fading out at the top.
struct PortingLogBox: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let logs: [LogEntry]
    @Binding var expanded: Bool

    static let softGreen = Color(hex: 0xA8DDB5)
    /// The newest lines only: a long porting writes thousands.
    private static let shown = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { expanded.toggle() }
            } label: {
                HStack(spacing: canvas.u(8)) {
                    Image(systemName: "chevron.right")
                        .seleneFont(12, .bold)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Log")
                        .seleneFont(15, .semibold)
                    Spacer()
                    if let last = logs.last, !expanded {
                        Text(last.message)
                            .seleneFont(12, .regular, design: .monospaced)
                            .foregroundColor(SeleneTheme.ink60)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .foregroundColor(SeleneTheme.ink75)
                .padding(.horizontal, canvas.u(16))
                .frame(height: canvas.u(40))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                lines
                    .frame(height: canvas.u(220))
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .fill(SeleneTheme.glassLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1)))
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous))
    }

    private var lines: some View {
        let recent = Array(logs.suffix(Self.shown))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: canvas.u(3)) {
                    ForEach(recent) { entry in
                        Text(entry.message)
                            .seleneFont(12, .regular, design: .monospaced)
                            .foregroundColor(color(entry.level))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, canvas.u(16))
                .padding(.top, canvas.u(18))
                .padding(.bottom, canvas.u(12))
            }
            .scrollIndicators(.hidden)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: canvas.u(36))
                    Color.black
                }
            )
            .onAppear { if let last = recent.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            .onChange(of: logs.count) { _ in
                guard let last = logs.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func color(_ level: LogLevel) -> Color {
        switch level {
        case .error: return PortingPillCopy.softRed
        case .success: return Self.softGreen
        case .warning: return SeleneTheme.untested.opacity(0.85)
        case .info, .step: return SeleneTheme.ink60
        }
    }
}
