import SwiftUI
import AppKit
import NXLibraryCore

struct GameOptionsView: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let onClose: () -> Void
    let onShowBuild: () -> Void

    @State private var config: GameRuntimeConfig
    @State private var showRemoveSources = false
    @State private var showDelete = false

    init(viewModel: AppViewModel, game: PortedGame,
         onClose: @escaping () -> Void, onShowBuild: @escaping () -> Void) {
        self.viewModel = viewModel
        self.game = game
        self.onClose = onClose
        self.onShowBuild = onShowBuild
        _config = State(initialValue: viewModel.loadRuntimeConfig(for: game))
    }

    private var presentation: GameOptionsPresentation {
        GameOptionsPresentation(
            supportsRenderScale: viewModel.supportsSetting("DM_RENDER_SCALE", for: game),
            isPlayable: game.isPlayableLocally,
            sourcesDetached: !game.sources.contains { $0.type == .base }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(980, geo.size.width - 64)
            let height = min(760, geo.size.height - 64)
            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }

                VStack(spacing: 0) {
                    header
                    Divider().opacity(0.15)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 9) {
                                playRow
                                displayRows
                                performanceRows
                                consoleRow
                                languageRow
                                controllerRows
                                renderScaleRows
                                saveAndBuildRows
                                restoreRow
                                dangerZone
                            }
                            .padding(18)
                            .id("top")
                        }
                        .scrollIndicators(.hidden)
                        .onAppear {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
                .frame(width: width, height: height)
                .background(SeleneTheme.canvasRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 40, x: 0, y: 20)
            }
        }
        .onExitCommand { onClose() }
        .onChange(of: config) { newValue in
            viewModel.saveRuntimeConfig(newValue, for: game)
        }
        .confirmationDialog("Remove sources and build cache?",
                            isPresented: $showRemoveSources,
                            titleVisibility: .visible) {
            Button("Remove Sources", role: .destructive) {
                viewModel.removeSources(for: game)
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.sourceRemovalSummary(for: game))
        }
        .confirmationDialog(deleteTitle, isPresented: $showDelete,
                            titleVisibility: .visible) {
            Button(deleteButtonTitle, role: .destructive) {
                viewModel.deletePortedGame(game)
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(nsImage: GameIconProvider.icon(for: game))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let version = game.versionString {
                        Text("v\(version)")
                    }
                    if let titleId = game.titleId {
                        Text(titleId)
                    }
                    Text("Game options")
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(SeleneTheme.inkMuted)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(SeleneTheme.ink.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(SeleneTheme.ink.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close game options")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var playRow: some View {
        SeleneRow("Play", subtitle: "Launch the installed Mac app.") {
            Button {
                onClose()
                viewModel.launchGame(game)
            } label: {
                Text("Play")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(presentation.canPlay ? SeleneTheme.canvas : SeleneTheme.inkMuted)
                    .padding(.horizontal, 20)
                    .frame(height: 30)
                    .background(presentation.canPlay ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.08))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!presentation.canPlay)
        }
    }

    private var displayRows: some View {
        Group {
            SeleneToggleRow("Fullscreen",
                            subtitle: "Output follows the display resolution.",
                            isOn: $config.fullscreen)
            SeleneToggleRow("Docked mode",
                            subtitle: "Use the maximum graphics profile; off is handheld.",
                            isOn: $config.isDockedMode)
        }
    }

    private var performanceRows: some View {
        Group {
            SeleneToggleRow("60 FPS",
                            subtitle: "Unlock the frame limiter when the game supports it.",
                            isOn: $config.enable60FPS)
            SeleneToggleRow("MetalFX",
                            subtitle: "Spatial upscaling; it does not raise the internal resolution.",
                            isOn: $config.enableMetalFXUpscale)
            SeleneToggleRow("Metal HUD",
                            subtitle: "Apple's real-time performance overlay.",
                            isOn: $config.enableMetalHUD)
        }
    }

    private var consoleRow: some View {
        SeleneRow("Console mode",
                  subtitle: "Docked uses the TV profile; handheld uses the portable profile.") {
            SeleneSegmented(
                selection: Binding(
                    get: { config.isDockedMode },
                    set: { config.isDockedMode = $0 }
                ),
                options: [(true, "Docked"), (false, "Handheld")]
            )
        }
    }

    private var languageRow: some View {
        SeleneRow("Game language",
                  subtitle: "Game Default leaves the engine's language untouched.") {
            Picker("", selection: $config.language) {
                ForEach(viewModel.availableLanguages, id: \.code) { item in
                    Text(item.label).tag(item.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 160)
        }
    }

    private var controllerRows: some View {
        Group {
            SeleneToggleRow("Rumble",
                            subtitle: "Controller vibration when the game supports it.",
                            isOn: $config.rumble)
            SeleneRow("Rumble strength",
                      subtitle: "Gain from 0 to 3.") {
                Stepper(value: $config.rumbleGain, in: 0...3) {
                    Text("\(config.rumbleGain)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(SeleneTheme.accent)
                }
                .frame(width: 90)
            }
        }
    }

    @ViewBuilder
    private var renderScaleRows: some View {
        if presentation.showRenderScale {
            SeleneRow("3D render scale",
                      subtitle: "100% keeps the game's own resolution.") {
                HStack(spacing: 10) {
                    Slider(value: $config.renderScale, in: 0.5...1.0, step: 0.05)
                        .frame(width: 170)
                    Text("\(Int(config.renderScale * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(SeleneTheme.accent)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        } else {
            SelenePanel("Internal resolution") {
                Text(presentation.resolutionNote)
                    .font(.system(size: 10.5))
                    .foregroundColor(SeleneTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var saveAndBuildRows: some View {
        Group {
            SeleneButtonRow("Save files",
                            subtitle: "Open the game's save folder.",
                            buttonTitle: "Open folder") {
                viewModel.revealSaveFolder(GameDetailsProfile.inspect(for: game).saveDirectory)
            }
            SeleneButtonRow("Build & sources",
                            subtitle: presentation.sourcesDetached
                                ? "Sources are detached. Attach them to rebuild."
                                : "Sources attached. Rebuild without touching saves.",
                            buttonTitle: "Attach sources…") {
                viewModel.locateSources(for: game)
            }
            SeleneRow("Rebuild",
                      subtitle: presentation.sourcesDetached
                        ? "A base source is required."
                        : "Build a new app; the old app stays if the build fails.") {
                HStack(spacing: 12) {
                    Button("Open log") { viewModel.revealLog(for: game) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.accent)
                    Button {
                        onClose()
                        viewModel.startBuild(for: game)
                        onShowBuild()
                    } label: {
                        Text("Rebuild")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(presentation.sourcesDetached ? SeleneTheme.inkMuted : SeleneTheme.canvas)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(presentation.sourcesDetached ? SeleneTheme.ink.opacity(0.08) : SeleneTheme.focus)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(presentation.sourcesDetached)
                }
            }
        }
    }

    private var restoreRow: some View {
        SeleneButtonRow("Restore defaults",
                        subtitle: "Reset this game's runtime settings.",
                        buttonTitle: "Restore") {
            config = GameRuntimeConfig()
        }
    }

    private var dangerZone: some View {
        VStack(spacing: 9) {
            SeleneButtonRow("Remove sources & build cache",
                            subtitle: "Deletes only the source files named in this game and its app-owned workspace. The app and saves stay.",
                            buttonTitle: "Remove…") {
                showRemoveSources = true
            }
            SeleneButtonRow(deleteTitle,
                            subtitle: deleteMessage,
                            buttonTitle: deleteButtonTitle) {
                showDelete = true
            }
        }
        .padding(.top, 4)
    }

    private var canDeleteBundle: Bool { game.canDeleteAppBundle() }

    private var deleteTitle: String {
        canDeleteBundle ? "Delete app bundle" : "Remove from library"
    }

    private var deleteButtonTitle: String {
        canDeleteBundle ? "Delete…" : "Remove…"
    }

    private var deleteMessage: String {
        if canDeleteBundle {
            return "This deletes \(game.url.path). Sources, saves and the build cache are not deleted."
        }
        return "This removes the library record only; \(game.url.path) stays on disk."
    }
}
