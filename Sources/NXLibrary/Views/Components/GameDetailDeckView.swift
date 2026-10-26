import SwiftUI
import AppKit
import NXLibraryCore

public struct GameDetailDeckView: View {
    public let game: PortedGame
    @ObservedObject public var viewModel: AppViewModel
    public let onDelete: (PortedGame) -> Void
    
    public init(game: PortedGame, viewModel: AppViewModel, onDelete: @escaping (PortedGame) -> Void) {
        self.game = game
        self.viewModel = viewModel
        self.onDelete = onDelete
    }
    
    public var body: some View {
        let profile = GameDetailsProfile.inspect(for: game)
        let config = viewModel.loadRuntimeConfig(for: game)
        let isLaunching = viewModel.launchingGameId == game.id
        let isDeckFocused = viewModel.isFocusOnDeck
        
        return GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                // Top Header Row: Title, TitleID, Platform, Action Buttons
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(game.name)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(NXTheme.textPrimary)
                            
                            Text("Mac Native")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(NXTheme.primary.opacity(0.35))
                                .foregroundColor(.white)
                                .clipShape(Capsule())

                            statusPill
                            toolchainPill
                        }
                        
                        if let tid = game.titleId, !tid.isEmpty {
                            Text("Title ID: \(tid)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(NXTheme.textMuted)
                        }
                    }
                    
                    Spacer()
                    
                    // Quick Config Pills
                    HStack(spacing: 6) {
                        configPill(title: config.enable60FPS ? "60 FPS" : "30 FPS", active: config.enable60FPS)
                        configPill(title: config.isDockedMode ? "Docked" : "Handheld", active: true)
                        if config.enableMetalFXUpscale {
                            configPill(title: "MetalFX", active: true)
                        }
                    }
                }
                
                if game.status == .builtSourcesMissing && game.sources.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(NXTheme.warning)
                        Text("Play works. Rebuilding is disabled until the original base, update and DLC files are attached with Add Game.")
                            .font(.system(size: 11))
                            .foregroundColor(NXTheme.textSecondary)
                        Spacer()
                    }
                    .padding(9)
                    .background(NXTheme.warning.opacity(0.09))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(NXTheme.warning.opacity(0.25), lineWidth: 0.8)
                    )
                }

                Divider().opacity(0.25)
                
                // Main Grid: Actions & Details
                LazyVGrid(columns: [GridItem(.flexible(minimum: 280)), GridItem(.flexible(minimum: 280))], spacing: 14) {
                    // Left Column: Play & Settings Actions
                    VStack(alignment: .leading, spacing: 12) {
                        // Play Button with anti-double-click loading state
                        if game.isPlayableLocally {
                            Button(action: {
                                SoundEffectService.shared.play(.click)
                                viewModel.launchGame(game)
                            }) {
                                HStack(spacing: 8) {
                                    if isLaunching {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Launching...")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                    } else {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 13))
                                        Text("Play Game")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(NXPrimaryButtonStyle())
                            .disabled(isLaunching || viewModel.launchingGameId != nil)
                            .shadow(color: isDeckFocused ? NXTheme.primary.opacity(0.6) : Color.clear, radius: 8)
                        }

                        Button(action: {
                            SoundEffectService.shared.play(.click)
                            viewModel.startBuild(for: game)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "hammer.fill")
                                Text(game.sources.isEmpty
                                     ? "Rebuild — sources missing"
                                     : (game.status == .notBuilt ? "Build App" : "Rebuild App"))
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NXSecondaryButtonStyle())
                        .controlSize(.regular)
                        .disabled(!viewModel.canBuild(game))
                        .opacity(viewModel.canBuild(game) ? 1 : 0.45)
                        .help(rebuildHint)

                        if viewModel.currentBuildGameID == game.id {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(viewModel.currentStageName.isEmpty
                                         ? "Building..." : viewModel.currentStageName)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(NXTheme.textPrimary)
                                    Spacer()
                                    Text("\(Int(viewModel.progressFraction * 100))%")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(NXTheme.secondary)
                                }
                                ProgressView(value: viewModel.progressFraction)
                                    .progressViewStyle(.linear)
                                    .tint(NXTheme.primary)
                                if !viewModel.currentStepName.isEmpty {
                                    Text(viewModel.currentStepName)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(NXTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(10)
                            .background(NXTheme.primary.opacity(0.08))
                            .cornerRadius(8)
                        }

                        HStack(spacing: 10) {
                            Button(action: {
                                SoundEffectService.shared.play(.click)
                                viewModel.gameForSettingsSheet = game
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("Settings")
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NXSecondaryButtonStyle())
                            .controlSize(.regular)
                            
                            Button(action: {
                                SoundEffectService.shared.play(.click)
                                viewModel.revealInFinder(url: game.url)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                    Text("App Files")
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NXSecondaryButtonStyle())
                            .controlSize(.regular)

                            Button(action: {
                                SoundEffectService.shared.play(.click)
                                viewModel.revealLog(for: game)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                    Text("Log")
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NXSecondaryButtonStyle())
                            .controlSize(.regular)
                            .help("Open the build or runtime log for this game.")
                            
                            Button(action: {
                                SoundEffectService.shared.play(.click)
                                onDelete(game)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                            }
                            .buttonStyle(NXSecondaryButtonStyle())
                            .controlSize(.regular)
                        }
                        
                        // Storage Size Info Card
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Storage Footprint")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(NXTheme.textSecondary)
                            
                            HStack {
                                Text("Total Game Size:")
                                    .font(.system(size: 11))
                                    .foregroundColor(NXTheme.textMuted)
                                Spacer()
                                Text(profile.formattedTotalSize)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(NXTheme.textPrimary)
                            }
                        }
                        .padding(10)
                        .background(NXTheme.glassSurfaceElevated.opacity(0.5))
                        .cornerRadius(8)
                    }
                    
                    // Right Column: DLCs & Save Files Location
                    VStack(alignment: .leading, spacing: 12) {
                        // Save Files Location
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Save Files Location", systemImage: "internaldrive")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(NXTheme.textSecondary)
                                Spacer()
                                Button("Open Folder") {
                                    SoundEffectService.shared.play(.click)
                                    viewModel.revealSaveFolder(profile.saveDirectory)
                                }
                                .buttonStyle(NXSecondaryButtonStyle())
                                .controlSize(.mini)
                            }
                            
                            Text(profile.saveDirectory.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(NXTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(NXTheme.canvasObsidian.opacity(0.6))
                                .cornerRadius(6)
                        }
                        .padding(10)
                        .background(NXTheme.glassSurfaceElevated.opacity(0.5))
                        .cornerRadius(8)
                        
                        // DLC Installed
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("DLC Installed", systemImage: "shippingbox.fill")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(NXTheme.textSecondary)
                                Spacer()
                                Text("\(profile.dlcItems.count) found")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(profile.dlcItems.isEmpty ? NXTheme.textMuted : NXTheme.secondary)
                            }
                            
                            if profile.dlcItems.isEmpty {
                                Text("Base Game Only (No DLC packages detected in bundle)")
                                    .font(.system(size: 10))
                                    .foregroundColor(NXTheme.textMuted)
                                    .padding(.vertical, 2)
                            } else {
                                ForEach(profile.dlcItems.prefix(2)) { dlc in
                                    HStack {
                                        Text("• \(dlc.name)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(NXTheme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(dlc.formattedSize)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(NXTheme.textSecondary)
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(NXTheme.glassSurfaceElevated.opacity(0.5))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isDeckFocused ? NXTheme.primary.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
    }
    
    private var statusPill: some View {
        Group {
            switch game.status {
            case .built:
                pill("Built", color: NXTheme.success)
            case .builtSourcesMissing:
                pill("Sources missing", color: NXTheme.warning)
            case .appMissing:
                pill("App missing", color: NXTheme.error)
            case .notBuilt:
                pill("Not built", color: NXTheme.textMuted)
            case .building:
                pill("Building", color: NXTheme.secondary)
            case .failed:
                pill("Build failed", color: NXTheme.error)
            case .cancelled:
                pill("Cancelled", color: NXTheme.textMuted)
            case .needsRebuild:
                pill("Needs rebuild", color: NXTheme.warning)
            }
        }
    }

    @ViewBuilder
    private var toolchainPill: some View {
        if game.status == .built && !game.toolchain.verified {
            if game.lastBuild != nil {
                pill("Untested toolchain", color: NXTheme.warning)
            } else if game.toolchain.note?.lowercased().contains("imported") == true {
                pill("Imported", color: NXTheme.textMuted)
            }
        }
    }

    private func pill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.25))
            .foregroundColor(color)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 0.6))
    }

    private var rebuildHint: String {
        if game.sources.isEmpty {
            return "Sources are missing. Attach the original base/update/DLC files before rebuilding."
        }
        if !viewModel.isProdKeysValid {
            return "Import prod.keys in Settings before rebuilding."
        }
        if !viewModel.isNxnativeValid {
            return "The nxnative checkout is missing. Choose it in Settings."
        }
        if viewModel.environmentStatus?.canBuild != true {
            return "The build environment is incomplete. Check Settings."
        }
        if !viewModel.canPassToolchainGate {
            return "The installed toolchain is not certified. Enable the untested-toolchain override in Settings."
        }
        return "Rebuild this app from its attached sources."
    }

    private func configPill(title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(active ? NXTheme.primary.opacity(0.35) : NXTheme.textMuted.opacity(0.3))
            .foregroundColor(.white)
            .clipShape(Capsule())
    }
}
