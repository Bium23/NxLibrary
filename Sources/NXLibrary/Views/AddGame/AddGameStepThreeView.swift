import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

struct AddGameStepThreeView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var porting: PortingModel
    @ObservedObject var router: AppRouter
    var artwork: ArtworkStore? = nil

    @Environment(\.seleneCanvas) private var canvas

    @Environment(\.seleneReduceMotion) private var reduceMotion

    @State private var didCopyDiagnostics = false

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
        content
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isBuilding) { publishActions() }
        .onChange(of: porting.isCancellingBuild) { publishActions() }
        .onChange(of: porting.buildSuccessPath) { publishActions() }
        .onChange(of: porting.buildError) { publishActions() }
        .onChange(of: porting.portingFailureReason) { publishActions() }
        .onChange(of: didCopyDiagnostics) { publishActions() }
        .onChange(of: porting.buildState) { publishActions() }
        .onChange(of: porting.buildHeldGameID) { publishActions() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isBuilding {
            buildingView
        } else if let path = porting.buildSuccessPath {
            successView(path: path)
        } else if let error = porting.buildError {
            failureView(error: error)
        } else if porting.buildState == .cancelled {
            cancelledView
        } else {
            idleView
        }
    }

    // MARK: - Building

    private var buildingView: some View {
        VStack(alignment: .leading, spacing: canvas.u(24)) {
            HStack(alignment: .top, spacing: canvas.u(36)) {
                gameTile(caption: viewModel.portingETAText
                    ?? (porting.currentStageName.isEmpty ? L10n.text("Preparing") : porting.currentStageName))
                stageList
            }
            PortingLogBox(logs: viewModel.logs, expanded: $porting.showLiveLogsInBuild)
        }
    }

    /// The game being ported, as its tile looks on the home, with a caption (the time left).
    @ViewBuilder private func gameTile(caption: String?) -> some View {
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
            if let caption {
                Text(caption)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
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
            if porting.buildStages.isEmpty {
                Text(L10n.text("Starting the porting…"))
                    .seleneFont(17)
                    .foregroundColor(SeleneTheme.ink60)
            }
            ForEach(porting.buildStages) { stage in
                HStack(spacing: canvas.u(12)) {
                    stageMark(stage)
                        .frame(width: canvas.u(22), height: canvas.u(22))
                    VStack(alignment: .leading, spacing: canvas.u(2)) {
                        Text(stage.name.prefix(1).uppercased() + stage.name.dropFirst())
                            .seleneFont(17, stage.isRunning ? .semibold : .regular)
                            .foregroundColor(stage.isRunning ? SeleneTheme.ink : SeleneTheme.ink75)
                        if stage.isRunning, !porting.currentStepName.isEmpty {
                            Text(porting.currentStepName)
                                .seleneFont(13, .regular, design: .monospaced)
                                .foregroundColor(SeleneTheme.ink60)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: canvas.u(12))
                    if let elapsed = stage.elapsedSeconds {
                        Text(PortingETA.elapsed(elapsed))
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
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: porting.buildStages)
    }

    @ViewBuilder private func stageMark(_ stage: BuildStageItem) -> some View {
        if stage.isFailed {
            Image(systemName: "xmark")
                .seleneFont(14, .bold)
                .foregroundColor(PortingPillCopy.softRed)
        } else if stage.hasWarning {
            Image(systemName: "exclamationmark.triangle.fill")
                .seleneFont(14, .bold)
                .foregroundColor(SeleneTheme.untested)
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

    // MARK: - Success

    /// The game whose new app waits for it to quit, if this porting's did.
    private var heldGameName: String? {
        porting.buildHeldGameID.flatMap { id in viewModel.libraryGames.first { $0.id == id }?.name }
    }

    private func successView(path: String) -> some View {
        SelenePanel {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .seleneFont(34)
                    .foregroundColor(SeleneTheme.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text(heldGameName == nil ? L10n.text("Ready to play") : PendingInstall.title)
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

            Text(heldGameName.map(PendingInstall.message(gameName:))
                 ?? L10n.text("The app was installed atomically. Your library now points at the new build."))
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink90)

            ForEach(porting.buildStages.filter(\.hasWarning)) { stage in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .seleneFont(14)
                        .foregroundColor(SeleneTheme.untested)
                    Text(BuildWarningCopy.text(stage: stage.name, summary: stage.summary))
                        .seleneFont(14)
                        .foregroundColor(SeleneTheme.ink90)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Failure

    /// The tile as the porting left it, what stopped it and the one next step; the step title
    /// carries the reason's title.
    private func failureView(error: String) -> some View {
        let reason = porting.portingFailureReason
        return VStack(alignment: .leading, spacing: canvas.u(24)) {
            HStack(alignment: .top, spacing: canvas.u(36)) {
                gameTile(caption: nil)
                VStack(alignment: .leading, spacing: canvas.u(12)) {
                    Text(error)
                        .seleneFont(19)
                        .foregroundColor(SeleneTheme.ink90)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(viewModel.canRetryReadyInstall ? L10n.text("Your build has been kept. Retry installs it without porting again.")
                         : reason?.next ?? L10n.text("The previous app was left untouched. The log has the failing command and output."))
                        .seleneFont(17)
                        .foregroundColor(SeleneTheme.ink60)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, canvas.u(8))
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(L10n.text("Porting cancelled"))
                            .seleneFont(34, .semibold)
                            .foregroundColor(SeleneTheme.ink)
                        Text(L10n.text("The previous app was left untouched. You can retry or go back to the review step."))
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
        PortingLogBox(logs: viewModel.logs, expanded: $porting.showLiveLogsInBuild)
    }

    // MARK: - Idle

    private var idleView: some View {
        SelenePanel {
            HStack(spacing: 14) {
                Image(systemName: "hammer.fill")
                    .seleneFont(34)
                    .foregroundColor(SeleneTheme.ink60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("No build is active"))
                        .seleneFont(19, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                    Text(L10n.text("Go back to the review step and choose Add & Build to start a build."))
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink90)
                }
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private var actionSpecs: [StepAction] {
        if viewModel.isBuilding {
            return [
                StepAction(id: "log",
                           title: porting.showLiveLogsInBuild ? L10n.text("Hide Log") : L10n.text("Show Log"),
                           systemImage: "terminal",
                           kind: .secondary,
                           isEnabled: true) {
                    porting.showLiveLogsInBuild.toggle()
                },
                StepAction(id: "cancel",
                           title: porting.isCancellingBuild ? L10n.text("Cancelling…") : L10n.text("Cancel porting"),
                           systemImage: "stop.circle.fill",
                           kind: .destructive,
                           isEnabled: !porting.isCancellingBuild) {
                    porting.cancelBuild()
                },
                StepAction(id: "openLog", title: L10n.text("Open log"),
                           systemImage: "doc.text.magnifyingglass",
                           kind: .secondary, isEnabled: true) {
                    porting.openBuildLog()
                },
                StepAction(id: "console", title: L10n.text("Open console"),
                           systemImage: nil, kind: .quiet, isEnabled: true) {
                    NotificationCenter.default.post(name: .nxLibraryOpenConsole, object: nil)
                }
            ]
        }

        if let path = porting.buildSuccessPath {
            let needsSave = viewModel.lastBuildGameID.map { viewModel.catalogBuildRecoveries[$0] != nil } ?? false
            var actions = [
                StepAction(id: "play", title: L10n.text("Play"),
                           systemImage: "play.fill", kind: needsSave ? .secondary : .primary,
                           isEnabled: FileManager.default.fileExists(atPath: path)) {
                    play(path: path)
                },
                StepAction(id: "library", title: L10n.text("Show in library"),
                           systemImage: "square.grid.2x2",
                           kind: .secondary, isEnabled: true) {
                    router.showLibrary()
                },
                StepAction(id: "another", title: L10n.text("Port another game"),
                           systemImage: "plus", kind: .secondary, isEnabled: true) {
                    withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                        porting.startNewAddGame()
                    }
                },
                StepAction(id: "openLog", title: L10n.text("Open log"),
                           systemImage: "doc.text.magnifyingglass",
                           kind: .secondary, isEnabled: true) {
                    porting.openBuildLog()
                },
                StepAction(id: "reveal", title: L10n.text("Reveal in Finder"),
                           systemImage: "folder", kind: .secondary, isEnabled: true) {
                    porting.openOutputInFinder()
                }
            ]
            if needsSave {
                actions.insert(StepAction(id: "saveLibrary", title: L10n.text("Retry saving library"),
                                          systemImage: "arrow.clockwise", kind: .primary, isEnabled: !viewModel.isBuilding) {
                    viewModel.retrySavingBuildResults()
                }, at: 0)
            }
            return actions
        }

        if porting.buildError != nil || porting.buildState == .cancelled {
            var specs: [StepAction] = []
            if porting.buildError != nil, let action = porting.portingFailureReason?.action,
               let spec = failureActionSpec(action) {
                specs.append(spec)
            }
            let leadsWithAction = !specs.isEmpty
            specs += [
                StepAction(id: "openLog", title: L10n.text("Open log"),
                           systemImage: "doc.text.magnifyingglass",
                           kind: .secondary, isEnabled: true) {
                    porting.openBuildLog()
                },
            ]
            if porting.buildError != nil {
                specs.append(StepAction(id: "diagnostics", title: didCopyDiagnostics ? L10n.text("Copied") : L10n.text("Copy diagnostics"),
                                        systemImage: nil, kind: .secondary, isEnabled: true) {
                    viewModel.copyDiagnostics()
                    didCopyDiagnostics = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { didCopyDiagnostics = false }
                })
            }
            specs += [
                StepAction(id: "retry", title: viewModel.canRetryReadyInstall ? L10n.text("Retry installation") : L10n.text("Try again"),
                           systemImage: "arrow.clockwise", kind: leadsWithAction ? .secondary : .primary,
                           isEnabled: !viewModel.isBuilding) {
                    porting.retryLastBuild()
                },
                StepAction(id: "options", title: L10n.text("Back to review"),
                           systemImage: "slider.horizontal.3",
                           kind: .secondary, isEnabled: true) {
                    withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                        porting.goToWizardStep(2)
                    }
                },
                StepAction(id: "console", title: L10n.text("Open console"),
                           systemImage: nil, kind: .quiet, isEnabled: true) {
                    NotificationCenter.default.post(name: .nxLibraryOpenConsole, object: nil)
                }
            ]
            return specs
        }

        return [
            StepAction(id: "review", title: L10n.text("Back to review"),
                       systemImage: "arrow.left", kind: .secondary,
                       isEnabled: true) {
                withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                    porting.goToWizardStep(porting.selectedGame == nil ? 1 : 2)
                }
            }
        ]
    }

    /// The failure's one next step as a row, first; nil when it has none.
    private func failureActionSpec(_ action: PortingFailureAction) -> StepAction? {
        let perform = { porting.performFailureAction(action, router: router) }
        switch action {
        case .portAnyway:
            return StepAction(id: "portAnyway", title: L10n.text("Port anyway"), systemImage: nil, kind: .primary,
                              isEnabled: !viewModel.isBuilding, perform: perform)
        case .openEngineSettings:
            return StepAction(id: "engine", title: L10n.text("Open Engine settings"), systemImage: nil, kind: .primary,
                              isEnabled: true, perform: perform)
        case .openSetup:
            return StepAction(id: "setup", title: L10n.text("Open Setup"), systemImage: nil, kind: .primary,
                              isEnabled: true, perform: perform)
        case .importKeys:
            return StepAction(id: "keys", title: L10n.text("Import prod.keys"), systemImage: nil, kind: .primary,
                              isEnabled: true, perform: perform)
        case .openStorage:
            return StepAction(id: "storage", title: L10n.text("Open Storage"), systemImage: nil, kind: .primary,
                              isEnabled: true, perform: perform)
        case .none:
            return nil
        }
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
                    Text(L10n.text("Log"))
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
            .onChange(of: logs.count) {
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
