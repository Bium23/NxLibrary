import SwiftUI
import NXLibraryCore

struct SettingsLibrarySection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var artwork: ArtworkStore
    let onActions: ([SettingsRowAction]) -> Void

    @State private var metadataBytes: Int64 = 0
    @State private var artworkBytes: Int64 = 0

    var body: some View {
        VStack(spacing: 9) {
            SeleneRow(GameFoldersCopy.appsTitle,
                      subtitle: GameFoldersCopy.appsContents,
                      info: "Choose where to keep your game apps. Put any existing nxnative games (.app) here. Changing folders does not move apps; rebuilds update them where they are.") {
                HStack(spacing: 10) {
                    Text(viewModel.libraryFolder?.path ?? "Not selected")
                        .seleneFont(15, .medium)
                        .foregroundColor(SeleneTheme.ink.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .trailing)
                    Button("Change") { viewModel.selectLibraryFolder() }
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                    Button("Reset") {
                        viewModel.libraryFolder = URL(fileURLWithPath: viewModel.defaultInstallPath)
                            .appendingPathComponent("Applications")
                        viewModel.loadLibrary()
                    }
                    .buttonStyle(.plain)
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                }
            }

            SeleneRow(GameFoldersCopy.sourcesTitle,
                      subtitle: GameFoldersCopy.sourcesAbout(extractedFolders: viewModel.engineSourceCapabilities.extractedFolders),
                      info: "Existing game apps play without their sources. Reset group keeps this folder. Clear removes the selection, keeping your files.") {
                HStack(spacing: 10) {
                    Text(viewModel.selectedGameFolder?.path ?? "Not selected · Optional")
                        .seleneFont(15, .medium)
                        .foregroundColor(SeleneTheme.ink.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .trailing)
                    Button("Choose") { viewModel.selectGameFolder() }
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                    if viewModel.selectedGameFolder != nil {
                        Button("Clear") { viewModel.selectedGameFolder = nil }
                            .buttonStyle(.plain)
                            .seleneFont(14, .semibold)
                            .foregroundColor(SeleneTheme.danger)
                    }
                }
            }

            SeleneButtonRow("Existing builds",
                            subtitle: "Find nxnative games (.app) in your Game apps folder.",
                            info: "Finds existing nxnative game apps in your Game apps folder. Source game files are optional for Play.",
                            buttonTitle: "Import") {
                viewModel.importExistingBuilds()
            }

            SeleneButtonRow("Library refresh",
                            subtitle: viewModel.isScanningLibrary
                                ? "Scanning the app library..." : "Rescan folders for new or removed apps.",
                            buttonTitle: "Refresh") {
                viewModel.refreshLibrary()
            }

            SeleneToggleRow("Notify when a porting ends",
                            subtitle: "A notification when a porting finishes while NX Library is in the background.",
                            isOn: $settings.settings.notifyPortingEnds)

            SeleneValueRow("Metadata cache",
                           subtitle: "Nintendo Store descriptions, genres and links.",
                           info: "Locally cached game metadata such as title IDs, publisher names, release dates, and category tags fetched during library scans.",
                           value: seleneBytes(metadataBytes),
                           actionTitle: "Clear") {
                viewModel.clearMetadataCache()
                metadataBytes = viewModel.metadataCacheSize()
            }

            SeleneValueRow("Artwork cache",
                           subtitle: "Hero and cover art downloaded for this library.",
                           info: "High-resolution game box art and hero wallpapers cached locally from the Nintendo Store catalog.",
                           value: seleneBytes(artworkBytes),
                           actionTitle: "Clear") {
                artwork.clear()
                artworkBytes = artwork.cacheSize()
            }
        }
        .task {
            metadataBytes = viewModel.metadataCacheSize()
            artworkBytes = artwork.cacheSize()
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isScanningLibrary) { _ in publishActions() }
    }

    private func publishActions() {
        onActions([
            .init(id: "appsChange", title: GameFoldersCopy.appsTitle) {
                viewModel.selectLibraryFolder()
            },
            .init(id: "romChoose", title: GameFoldersCopy.sourcesTitle) {
                viewModel.selectGameFolder()
            },
            .init(id: "import", title: "Existing builds") {
                viewModel.importExistingBuilds()
            },
            .init(id: "refresh", title: "Library refresh", isEnabled: !viewModel.isScanningLibrary) {
                viewModel.refreshLibrary()
            },
            .init(id: "notify", title: "Notify when a porting ends") {
                settings.settings.notifyPortingEnds.toggle()
            },
            .init(id: "metadataClear", title: "Metadata cache") {
                viewModel.clearMetadataCache()
                metadataBytes = viewModel.metadataCacheSize()
            },
            .init(id: "artworkClear", title: "Artwork cache") {
                artwork.clear()
                artworkBytes = artwork.cacheSize()
            }
        ])
    }
}
