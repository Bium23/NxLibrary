import SwiftUI
import AppKit
import NXLibraryCore

public struct LibraryView: View {
    @ObservedObject public var viewModel: AppViewModel
    @State private var gameToDelete: PortedGame? = nil
    @State private var showDeleteConfirm: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var filteredGames: [PortedGame] {
        viewModel.filteredLibraryGames
    }
    
    private var deleteTargetIsBundle: Bool {
        gameToDelete?.canDeleteAppBundle() == true
    }

    private var deleteTitle: String {
        deleteTargetIsBundle
            ? "Delete \(gameToDelete?.name ?? "this game")?"
            : "Remove \(gameToDelete?.name ?? "this game") from the library?"
    }

    private var deleteMessage: String {
        if deleteTargetIsBundle {
            return "This permanently deletes only this app bundle:\n\(gameToDelete?.url.path ?? "unknown path")\n\nSource files, saves and build caches are not deleted."
        }
        return "This removes only the library record. The folder and its contents are left in place:\n\(gameToDelete?.url.path ?? "unknown path")"
    }

    private var currentSelectedGame: PortedGame? {
        guard !filteredGames.isEmpty else { return nil }
        let index = max(0, min(viewModel.focusedGameIndex, filteredGames.count - 1))
        return filteredGames[index]
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Library Toolbar (Liquid Glass & Search)
            toolbarView

            HomeStatusStrip(viewModel: viewModel)
                .padding(.horizontal, 18)
                .padding(.top, 10)
            
            // MARK: - Console Game Showcase & Detail Deck
            if filteredGames.isEmpty {
                emptyLibraryView
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Console Carousel (Elevated Cover on Focus)
                        ConsoleGameCarouselView(viewModel: viewModel, games: filteredGames)
                        
                        // 2. Focused Game Detail Deck (Play, DLC, Sizes, Saves, Settings)
                        if let selected = currentSelectedGame {
                            GameDetailDeckView(game: selected, viewModel: viewModel) { target in
                                self.gameToDelete = target
                                self.showDeleteConfirm = true
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            
            Spacer(minLength: 0)
            
            // MARK: - Game Controller Prompt Bar
            ControllerPromptBar()
        }
        .sheet(item: $viewModel.gameForSettingsSheet) { game in
            GameSettingsSheetView(viewModel: viewModel, game: game)
        }
        .confirmationDialog(deleteTitle, isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button(deleteTargetIsBundle ? "Delete App Bundle" : "Remove from Library",
                   role: .destructive) {
                if let g = gameToDelete {
                    viewModel.deletePortedGame(g)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }
    
    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Search Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(NXTheme.textSecondary)
                TextField("Search your library...", text: $viewModel.librarySearchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(NXTheme.textPrimary)
                if !viewModel.librarySearchText.isEmpty {
                    Button(action: { viewModel.librarySearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(NXTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(NXTheme.glassSurfaceElevated.opacity(0.8))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NXTheme.specularRim, lineWidth: 0.8)
            )
            .frame(maxWidth: 280)
            
            Spacer()
            
            // Library Folder Indicator
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundColor(NXTheme.secondary)
                Text(viewModel.libraryFolder?.lastPathComponent ?? "Default Games")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(NXTheme.textSecondary)
                
                Button("Change...") {
                    SoundEffectService.shared.play(.click)
                    viewModel.selectLibraryFolder()
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.small)
            }
            
            Button(action: {
                SoundEffectService.shared.play(.click)
                viewModel.refreshLibrary()
            }) {
                HStack(spacing: 4) {
                    if viewModel.isScanningLibrary {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
            }
            .buttonStyle(NXSecondaryButtonStyle())
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            ZStack {
                NXTheme.canvasObsidian.opacity(0.6)
                Rectangle().fill(.ultraThinMaterial)
            }
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(NXTheme.borderSubtle),
            alignment: .bottom
        )
    }
    
    private var emptyLibraryView: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 44))
                .foregroundColor(NXTheme.secondary.opacity(0.4))
            
            VStack(spacing: 4) {
                Text("Your library is empty")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Text("Add a game or import an app already built with nxnative.")
                    .font(.system(size: 12))
                    .foregroundColor(NXTheme.textSecondary)
            }

            HStack(spacing: 10) {
                Button("Add a Game") {
                    SoundEffectService.shared.play(.click)
                    viewModel.selectedTab = 1
                }
                .buttonStyle(NXPrimaryButtonStyle())
                .controlSize(.regular)

                Button("Import Existing Builds") {
                    SoundEffectService.shared.play(.click)
                    viewModel.importExistingBuilds()
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(40)
    }
}
